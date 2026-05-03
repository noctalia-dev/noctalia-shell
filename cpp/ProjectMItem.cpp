/*
 * ProjectMItem.cpp
 *
 * Qt Quick FBO item that renders libprojectM-4 with PulseAudio input.
 * Audio capture logic ported directly from waylivepaper/src/main.c.
 */

#include "ProjectMItem.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QOpenGLExtraFunctions>
#include <QQuickFramebufferObject>
#include <QQuickWindow>
#include <QRandomGenerator>
#include <QThread>
#include <QtCore/QLoggingCategory>

#include <projectM-4/audio.h>
#include <projectM-4/core.h>
#include <projectM-4/parameters.h>
#include <projectM-4/render_opengl.h>
#include <projectM-4/types.h>

#include <pulse/error.h>
#include <pulse/simple.h>

#include <algorithm>
#include <limits>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

Q_LOGGING_CATEGORY(lcPM, "noctalia.projectm")

// ============================================================
// Constants — identical to waylivepaper
// ============================================================
static constexpr int AUDIO_CHUNK = 512;
static constexpr int SAMPLE_RATE = 44100;
static constexpr double SILENCE_SWITCH_SECONDS = 10.0;
static constexpr float SILENCE_PEAK_THRESHOLD = 0.003f;
static constexpr float WAKE_PEAK_THRESHOLD = 0.02f;
static constexpr double WAKE_SUSTAIN_SECONDS = 0.3;
static constexpr double PROBE_REDETECT_INTERVAL = 5.0;
static constexpr float AGC_TARGET_PEAK = 0.6f;
static constexpr float AGC_MAX_GAIN = 40.0f;
static constexpr float AGC_ATTACK = 0.5f;
static constexpr float AGC_RELEASE = 0.002f;
static constexpr float AGC_FLOOR = 0.001f;
// Cap the per-renderer PCM queue at ~3 seconds of audio (256 chunks × 512 frames × 2 ch).
// If the render thread stalls, incoming chunks are dropped rather than growing without bound.
static constexpr std::size_t PCM_MAX_SAMPLES =
    static_cast<std::size_t>(AUDIO_CHUNK) * 2 * 256;

// ============================================================
// AudioBroadcast — shared fan-out list for one capture → N renderers
// ============================================================
struct AudioBroadcast {
    std::mutex mtx;
    std::vector<std::weak_ptr<PcmAccum>> subscribers;
};

// ============================================================
// AudioCapture — background QThread, ported from waylivepaper
// ============================================================
class AudioCapture : public QThread {
    Q_OBJECT
public:
    explicit AudioCapture(std::shared_ptr<AudioBroadcast> broadcast,
                          const QString &explicitSource,
                          QObject *parent = nullptr)
        : QThread(parent)
        , m_broadcast(std::move(broadcast))
        , m_explicitSource(explicitSource.toStdString())
        , m_userSupplied(!explicitSource.isEmpty())
    {
    }

    void requestStop() { m_running.store(false, std::memory_order_release); }

protected:
    void run() override;

private:
    // ---- helpers ----------------------------------------------------------
    static std::string detectDefaultMonitor();
    static pa_simple *openSource(const char *name);
    void probeLoop(); // runs in a std::thread while on mic

    // ---- state ------------------------------------------------------------
    std::atomic<bool> m_running{true};
    std::shared_ptr<AudioBroadcast> m_broadcast;

    std::string m_explicitSource; // empty = auto-detect
    bool m_userSupplied = false;

    // monitor source name, shared between primary loop and probe thread
    std::mutex m_monitorNameMutex;
    std::string m_monitorSourceName;

    // probe thread
    std::thread m_probeThread;
    std::atomic<bool> m_probeRunning{false};
    std::atomic<float> m_monitorProbePeak{0.0f};

    void startProbe();
    void stopProbe();
};

// ---- detectDefaultMonitor — mirrors waylivepaper detect_default_monitor() --
std::string AudioCapture::detectDefaultMonitor()
{
    std::string defaultSink;
    FILE *ds = ::popen("pactl get-default-sink 2>/dev/null", "r");
    if (ds) {
        char buf[512] = {};
        if (::fgets(buf, sizeof buf, ds)) {
            buf[::strcspn(buf, "\r\n")] = '\0';
            defaultSink = buf;
        }
        if (::pclose(ds) != 0)
            qCWarning(lcPM) << "audio: pactl get-default-sink failed";
    }

    const std::string wantMonitor = defaultSink.empty() ? std::string()
                                                        : defaultSink + ".monitor";

    FILE *f = ::popen("pactl list sources short 2>/dev/null", "r");
    if (!f)
        return wantMonitor;

    char line[1024];
    std::string result;
    std::string fallback;
    while (::fgets(line, sizeof line, f)) {
        char idx[64], name[512];
        if (::sscanf(line, "%63s %511s", idx, name) != 2)
            continue;
        if (!::strstr(name, ".monitor"))
            continue;
        if (fallback.empty())
            fallback = name;
        if (!wantMonitor.empty() && wantMonitor == name) {
            result = name;
            break;
        }
    }
    if (::pclose(f) != 0)
        qCWarning(lcPM) << "audio: pactl list sources failed";

    return result.empty() ? fallback : result;
}

// ---- openSource ------------------------------------------------------------
pa_simple *AudioCapture::openSource(const char *name)
{
    pa_sample_spec ss{};
    ss.format = PA_SAMPLE_FLOAT32NE;
    ss.rate = SAMPLE_RATE;
    ss.channels = 2;

    pa_buffer_attr ba{};
    ba.maxlength = static_cast<uint32_t>(-1);
    ba.fragsize = AUDIO_CHUNK * 2 * sizeof(float);

    int perr = 0;
    pa_simple *s = pa_simple_new(nullptr, "noctalia-shell",
                                 PA_STREAM_RECORD, name,
                                 "visualizer", &ss, nullptr, &ba, &perr);
    if (!s) {
        qCWarning(lcPM) << "pa_simple_new(" << (name ? name : "<default mic>")
                        << "):" << pa_strerror(perr);
    }
    return s;
}

// ---- probe thread ----------------------------------------------------------
void AudioCapture::probeLoop()
{
    float buf[AUDIO_CHUNK * 2];
    pa_simple *stream = nullptr;
    const double chunkSecs = static_cast<double>(AUDIO_CHUNK) / SAMPLE_RATE;
    double streamAge = 0.0;

    while (m_probeRunning.load(std::memory_order_acquire)) {
        if (!stream) {
            // Re-detect monitor source unless user supplied one
            if (!m_userSupplied) {
                std::string fresh = detectDefaultMonitor();
                if (!fresh.empty()) {
                    std::lock_guard<std::mutex> lk(m_monitorNameMutex);
                    if (fresh != m_monitorSourceName) {
                        qCDebug(lcPM) << "probe: monitor source updated:" << fresh.c_str();
                        m_monitorSourceName = fresh;
                    }
                }
            }

            std::string monName;
            {
                std::lock_guard<std::mutex> lk(m_monitorNameMutex);
                monName = m_monitorSourceName;
            }
            stream = openSource(monName.empty() ? nullptr : monName.c_str());
            if (!stream) {
                QThread::msleep(1000);
                continue;
            }
            streamAge = 0.0;
        }

        int err = 0;
        if (pa_simple_read(stream, buf, sizeof buf, &err) < 0) {
            qCWarning(lcPM) << "probe: pa_simple_read:" << pa_strerror(err) << "— reopening";
            pa_simple_free(stream);
            stream = nullptr;
            continue;
        }

        float peak = 0.0f;
        for (int i = 0; i < AUDIO_CHUNK * 2; ++i) {
            float v = std::fabs(buf[i]);
            if (v > peak) peak = v;
        }
        m_monitorProbePeak.store(peak, std::memory_order_relaxed);

        streamAge += chunkSecs;
        if (streamAge >= PROBE_REDETECT_INTERVAL) {
            pa_simple_free(stream);
            stream = nullptr;
        }
    }

    if (stream)
        pa_simple_free(stream);
    m_monitorProbePeak.store(0.0f, std::memory_order_relaxed);
}

void AudioCapture::startProbe()
{
    std::string monName;
    {
        std::lock_guard<std::mutex> lk(m_monitorNameMutex);
        monName = m_monitorSourceName;
    }
    if (monName.empty())
        return;
    if (m_probeRunning.exchange(true, std::memory_order_acq_rel))
        return; // was already running — avoids TOCTOU on concurrent calls
    m_monitorProbePeak.store(0.0f, std::memory_order_relaxed);
    m_probeThread = std::thread(&AudioCapture::probeLoop, this);
}

void AudioCapture::stopProbe()
{
    if (!m_probeRunning.load(std::memory_order_acquire))
        return;
    m_probeRunning.store(false, std::memory_order_release);
    if (m_probeThread.joinable())
        m_probeThread.join();
    m_monitorProbePeak.store(0.0f, std::memory_order_relaxed);
}

// ---- primary audio loop ---------------------------------------------------
void AudioCapture::run()
{
    // Determine initial monitor source — hold the mutex even though the probe
    // thread hasn't started yet, for consistency and future-safety.
    {
        std::lock_guard<std::mutex> lk(m_monitorNameMutex);
        if (m_userSupplied) {
            m_monitorSourceName = m_explicitSource;
        } else {
            m_monitorSourceName = detectDefaultMonitor();
            if (!m_monitorSourceName.empty())
                qCDebug(lcPM) << "audio: auto-detected monitor source:"
                              << m_monitorSourceName.c_str();
        }
    }

    enum SrcType { SRC_MONITOR, SRC_MIC } currentSource = SRC_MONITOR;

    float buf[AUDIO_CHUNK * 2];
    double silentFor = 0.0;
    double monitorWakeFor = 0.0;
    float agcEnvelope = 0.01f;
    const double chunkSecs = static_cast<double>(AUDIO_CHUNK) / SAMPLE_RATE;

    pa_simple *paStream = nullptr;

    while (m_running.load(std::memory_order_acquire)) {

        if (!paStream) {
            std::string name;
            if (currentSource == SRC_MONITOR) {
                std::lock_guard<std::mutex> lk(m_monitorNameMutex);
                name = m_monitorSourceName;
            }
            // SRC_MIC: name stays empty → pa_simple_new picks default mic
            paStream = openSource(name.empty() ? nullptr : name.c_str());
            if (!paStream) {
                QThread::msleep(1000);
                continue;
            }
            silentFor = 0.0;
            monitorWakeFor = 0.0;
            agcEnvelope = 0.01f;
            qCDebug(lcPM) << "audio: reading from"
                          << (name.empty() ? "<default mic>" : name.c_str());

            if (currentSource == SRC_MIC) {
                startProbe();
            } else {
                stopProbe();
            }
        }

        int perr = 0;
        if (pa_simple_read(paStream, buf, sizeof buf, &perr) < 0) {
            qCWarning(lcPM) << "pa_simple_read:" << pa_strerror(perr) << "— reopening";
            pa_simple_free(paStream);
            paStream = nullptr;
            continue;
        }

        // Raw peak (before AGC)
        float peak = 0.0f;
        for (int i = 0; i < AUDIO_CHUNK * 2; ++i) {
            float v = std::fabs(buf[i]);
            if (v > peak) peak = v;
        }

        // AGC on mic path only
        if (currentSource == SRC_MIC) {
            if (peak > agcEnvelope)
                agcEnvelope += (peak - agcEnvelope) * AGC_ATTACK;
            else
                agcEnvelope += (peak - agcEnvelope) * AGC_RELEASE;

            if (agcEnvelope < AGC_FLOOR)
                agcEnvelope = AGC_FLOOR;

            float gain = AGC_TARGET_PEAK / agcEnvelope;
            if (gain > AGC_MAX_GAIN) gain = AGC_MAX_GAIN;

            for (int i = 0; i < AUDIO_CHUNK * 2; ++i) {
                float s = buf[i] * gain;
                if (s > 1.0f) s = 1.0f;
                if (s < -1.0f) s = -1.0f;
                buf[i] = s;
            }
        }

        // Broadcast PCM to all subscribed renderers.
        // Drop the chunk for any renderer whose queue is already at the cap
        // (renderer stalled) rather than growing the buffer without bound.
        {
            std::lock_guard<std::mutex> blk(m_broadcast->mtx);
            for (auto &wp : m_broadcast->subscribers) {
                if (auto accum = wp.lock()) {
                    std::lock_guard<std::mutex> alk(accum->mtx);
                    if (accum->samples.size() + static_cast<std::size_t>(AUDIO_CHUNK * 2)
                            <= PCM_MAX_SAMPLES)
                        accum->samples.insert(accum->samples.end(),
                                              buf, buf + AUDIO_CHUNK * 2);
                }
            }
        }

        // Source-switch logic
        if (currentSource == SRC_MONITOR) {
            if (peak < SILENCE_PEAK_THRESHOLD)
                silentFor += chunkSecs;
            else
                silentFor = 0.0;

            std::string monName;
            {
                std::lock_guard<std::mutex> lk(m_monitorNameMutex);
                monName = m_monitorSourceName;
            }
            if (silentFor >= SILENCE_SWITCH_SECONDS && !monName.empty()) {
                qCDebug(lcPM) << "audio:" << silentFor << "s silence on monitor → mic";
                currentSource = SRC_MIC;
                pa_simple_free(paStream);
                paStream = nullptr;
            }
        } else {
            float probePeak = m_monitorProbePeak.load(std::memory_order_relaxed);
            if (probePeak > WAKE_PEAK_THRESHOLD)
                monitorWakeFor += chunkSecs;
            else
                monitorWakeFor = 0.0;

            std::string monName;
            {
                std::lock_guard<std::mutex> lk(m_monitorNameMutex);
                monName = m_monitorSourceName;
            }
            if (monitorWakeFor >= WAKE_SUSTAIN_SECONDS && !monName.empty()) {
                qCDebug(lcPM) << "audio: monitor active (peak=" << probePeak
                              << ") → back to monitor";
                currentSource = SRC_MONITOR;
                pa_simple_free(paStream);
                paStream = nullptr;
            }
        }
    }

    stopProbe();
    if (paStream)
        pa_simple_free(paStream);
}

// ============================================================
// ProjectMRenderer — inner renderer, lives on the render thread
// ============================================================
class ProjectMRenderer : public QQuickFramebufferObject::Renderer,
                         protected QOpenGLExtraFunctions {
public:
    ProjectMRenderer() = default;
    ~ProjectMRenderer() override;

    QOpenGLFramebufferObject *
    createFramebufferObject(const QSize &size) override;
    void synchronize(QQuickFramebufferObject *item) override;
    void render() override;

private:
    void initProjectM(const QSize &size);
    void initDarken();
    GLuint compileShader(GLenum type, const char *src);

    projectm_handle m_pm = nullptr;
    bool m_pmInited = false;
    bool m_glInited = false;
    bool m_hasPreset = false;  // true after first successful preset load
    QSize m_size;
    QSize m_pmSize;            // size projectM was last set to
    QString m_loadedPreset;    // last hard-loaded preset path (for reload on resize)
    qreal m_dpr = 1.0;        // device pixel ratio — synced from window each frame

    // Darken overlay
    GLuint m_darkenProg = 0;
    GLuint m_darkenVao = 0;
    GLuint m_darkenVbo = 0;
    GLint m_darkenAlphaLoc = -1;
    bool m_darkenReady = false;

    // Synced from item
    float m_darken = 0.7f;
    int m_fps = 30;
    int m_meshW = 24;
    int m_meshH = 18;
    double m_presetInterval = 120.0;
    bool m_running = true;
    QString m_pendingPreset;
    std::shared_ptr<PcmAccum> m_accum;
};

// ---- destructor -----------------------------------------------------------
ProjectMRenderer::~ProjectMRenderer()
{
    // Both projectm_destroy and glDelete* issue GL calls internally.
    // Guard all of them: if the context is gone (e.g. sceneGraphInvalidated
    // fired before the renderer was collected), skip to avoid a crash and
    // accept the GPU resource leak.  Qt guarantees a current context during
    // normal render-thread teardown, so this only fires on abnormal paths.
    if (!QOpenGLContext::currentContext()) {
        qCWarning(lcPM) << "renderer: no GL context — leaking projectM handle and darken resources";
        m_pm = nullptr; // prevent double-destroy if somehow called again
        return;
    }
    if (m_pm) {
        projectm_destroy(m_pm);
        m_pm = nullptr;
    }
    if (m_darkenReady) {
        glDeleteProgram(m_darkenProg);
        glDeleteBuffers(1, &m_darkenVbo);
        glDeleteVertexArrays(1, &m_darkenVao);
    }
}

// ---- initProjectM ---------------------------------------------------------
void ProjectMRenderer::initProjectM(const QSize &size)
{
    m_pm = projectm_create();
    if (!m_pm) {
        qCCritical(lcPM) << "projectm_create() failed";
        return;
    }
    projectm_set_window_size(m_pm,
                             static_cast<size_t>(size.width()),
                             static_cast<size_t>(size.height()));
    projectm_set_mesh_size(m_pm,
                           static_cast<size_t>(m_meshW),
                           static_cast<size_t>(m_meshH));
    projectm_set_fps(m_pm, m_fps);
    projectm_set_preset_duration(m_pm, m_presetInterval);
    projectm_set_soft_cut_duration(m_pm, 3.0);
    projectm_set_hard_cut_enabled(m_pm, false);
    projectm_set_beat_sensitivity(m_pm, 1.0f);
    projectm_set_aspect_correction(m_pm, true);
    m_pmInited = true;
}

// ---- createFramebufferObject ----------------------------------------------
QOpenGLFramebufferObject *
ProjectMRenderer::createFramebufferObject(const QSize &size)
{
    qCWarning(lcPM) << "createFramebufferObject" << size << "dpr=" << m_dpr;
    m_size = size;
    // Logical (FBO 0) size: Qt FBO is at device pixels, FBO 0 is at logical px.
    const QSize logicalSize(qRound(size.width()  / m_dpr),
                            qRound(size.height() / m_dpr));
    if (m_pm) {
        if (logicalSize != m_pmSize) {
            qCWarning(lcPM) << "createFramebufferObject: logical size changed"
                            << m_pmSize << "->" << logicalSize
                            << "— reloading preset";
            projectm_set_window_size(m_pm,
                                     static_cast<size_t>(logicalSize.width()),
                                     static_cast<size_t>(logicalSize.height()));
            m_pmSize = logicalSize;
            if (!m_loadedPreset.isEmpty())
                m_pendingPreset = m_loadedPreset;
        }
    }
    return new QOpenGLFramebufferObject(
        size, QOpenGLFramebufferObject::CombinedDepthStencil);
}

// ---- synchronize ----------------------------------------------------------
void ProjectMRenderer::synchronize(QQuickFramebufferObject *baseItem)
{
    auto *item = static_cast<ProjectMItem *>(baseItem);

    // Device pixel ratio: the Qt FBO is created at logical_size × dpr, but
    // FBO 0 (the EGL window surface) is at logical_size (dpr=1 in Wayland).
    // We must render projectM at the logical size and blit up to the Qt FBO.
    if (item->window())
        m_dpr = item->window()->devicePixelRatio();

    m_darken = item->darken();
    m_fps = item->fps();
    m_meshW = item->meshWidth();
    m_meshH = item->meshHeight();
    m_presetInterval = item->presetInterval();
    m_running = item->running();

    QString preset = item->consumePreset();
    if (!preset.isEmpty())
        m_pendingPreset = preset;

    // pcmAccum() never changes after construction — assign once to avoid
    // atomic refcount traffic on every frame.
    if (!m_accum)
        m_accum = item->pcmAccum();
}

// ---- compileShader --------------------------------------------------------
GLuint ProjectMRenderer::compileShader(GLenum type, const char *src)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &src, nullptr);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = {};
        glGetShaderInfoLog(s, static_cast<GLsizei>(sizeof log), nullptr, log);
        qCWarning(lcPM) << "darken shader compile failed:" << log;
        glDeleteShader(s);
        return 0;
    }
    return s;
}

// ---- initDarken -----------------------------------------------------------
void ProjectMRenderer::initDarken()
{
    if (m_darkenReady) return;

    static const char *vsSrc =
        "#version 330 core\n"
        "layout(location=0) in vec2 pos;\n"
        "void main() { gl_Position = vec4(pos, 0.0, 1.0); }\n";

    static const char *fsSrc =
        "#version 330 core\n"
        "uniform float u_alpha;\n"
        "out vec4 fragColor;\n"
        "void main() { fragColor = vec4(0.0, 0.0, 0.0, u_alpha); }\n";

    GLuint vs = compileShader(GL_VERTEX_SHADER, vsSrc);
    GLuint fs = compileShader(GL_FRAGMENT_SHADER, fsSrc);
    if (!vs || !fs) {
        if (vs) glDeleteShader(vs);
        if (fs) glDeleteShader(fs);
        return;
    }

    m_darkenProg = glCreateProgram();
    glAttachShader(m_darkenProg, vs);
    glAttachShader(m_darkenProg, fs);
    glLinkProgram(m_darkenProg);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = 0;
    glGetProgramiv(m_darkenProg, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024] = {};
        glGetProgramInfoLog(m_darkenProg, static_cast<GLsizei>(sizeof log), nullptr, log);
        qCWarning(lcPM) << "darken link failed:" << log;
        glDeleteProgram(m_darkenProg);
        m_darkenProg = 0;
        return;
    }
    m_darkenAlphaLoc = glGetUniformLocation(m_darkenProg, "u_alpha");

    // Full-screen quad in NDC [-1,1] — same 6 vertices as waylivepaper
    static const float quad[] = {
        -1.f, -1.f,  1.f, -1.f,  -1.f,  1.f,
        -1.f,  1.f,  1.f, -1.f,   1.f,  1.f,
    };
    glGenVertexArrays(1, &m_darkenVao);
    glGenBuffers(1, &m_darkenVbo);
    glBindVertexArray(m_darkenVao);
    glBindBuffer(GL_ARRAY_BUFFER, m_darkenVbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    glEnableVertexAttribArray(0);
    glBindVertexArray(0);

    m_darkenReady = true;
}

// ---- render ---------------------------------------------------------------
void ProjectMRenderer::render()
{
    // One-time OpenGL init (must happen on the render thread)
    if (!m_glInited) {
        qCDebug(lcPM) << "render: first call — initializing GL functions";
        initializeOpenGLFunctions();
        initDarken();
        m_glInited = true;
        qCDebug(lcPM) << "render: darken ready=" << m_darkenReady;
    }

    // Qt's FBO is at device pixels; FBO 0 (the EGL window surface) is at
    // logical pixels (= device pixels / dpr) under Wayland fractional scaling.
    // projectM must render at the FBO 0 size, not the Qt FBO size.
    const int w = framebufferObject()->width();
    const int h = framebufferObject()->height();
    const GLuint qtFbo = framebufferObject()->handle();
    const int pm_w = qRound(w / m_dpr);
    const int pm_h = qRound(h / m_dpr);

    // Lazy-init projectM using the logical (FBO 0) size.
    if (!m_pmInited) {
        qCWarning(lcPM) << "render: init — FBO:" << w << "x" << h
                        << "  logical:" << pm_w << "x" << pm_h
                        << "  dpr:" << m_dpr;
        initProjectM(QSize(pm_w, pm_h));
        m_pmSize = QSize(pm_w, pm_h);
        if (!m_pm) {
            qCWarning(lcPM) << "render: m_pm is null — projectm_create() failed";
            return; // fatal — don't spin
        }
    }

    if (!m_pm) {
        qCWarning(lcPM) << "render: m_pm is null — projectm_create() failed";
        return; // fatal — don't spin
    }

    // Load pending preset BEFORE the first render_frame() (reference pattern).
    if (!m_pendingPreset.isEmpty()) {
        qCWarning(lcPM) << "render: loading preset at logical"
                        << pm_w << "x" << pm_h << m_pendingPreset;
        m_loadedPreset = m_pendingPreset;
        projectm_load_preset_file(m_pm,
                                  m_loadedPreset.toUtf8().constData(),
                                  false);
        m_pendingPreset.clear();
        m_hasPreset = true;
    }

    // Hold back rendering until the first preset is loaded.
    if (!m_hasPreset) {
        framebufferObject()->bind();
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        update();
        return;
    }

    // Drain PCM accumulator
    if (m_accum) {
        std::vector<float> drained;
        {
            std::lock_guard<std::mutex> lk(m_accum->mtx);
            drained = std::move(m_accum->samples);
        }
        // Feed in AUDIO_CHUNK-frame chunks
        const int stride = AUDIO_CHUNK * 2; // stereo
        for (std::size_t offset = 0;
             offset + static_cast<std::size_t>(stride) <= drained.size();
             offset += static_cast<std::size_t>(stride)) {
            projectm_pcm_add_float(m_pm,
                                   drained.data() + offset,
                                   AUDIO_CHUNK,
                                   PROJECTM_STEREO);
        }
    }

    // projectM renders to FBO 0 (the EGL window surface) at logical pixels.
    // Blit the result up to Qt's device-pixel FBO.
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glViewport(0, 0, pm_w, pm_h);
    projectm_opengl_render_frame(m_pm);
    // projectM leaves various GL state dirty (VAO, program, textures, blend,
    // depth).  Reset the state Qt Quick cares about most before continuing,
    // so the scene graph's internal state machine isn't corrupted.
    glBindVertexArray(0);
    glUseProgram(0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_SCISSOR_TEST);

    // Blit from FBO 0 (logical: pm_w×pm_h) to Qt's FBO (device: w×h).
    // Use GL_LINEAR when upscaling (dpr > 1) for smooth results.
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, qtFbo);
    const GLenum blitFilter = (pm_w != w || pm_h != h) ? GL_LINEAR : GL_NEAREST;
    glBlitFramebuffer(0, 0, pm_w, pm_h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, blitFilter);

    // Rebind Qt's FBO for subsequent passes and reset viewport
    framebufferObject()->bind();
    glViewport(0, 0, w, h);

    // Darken overlay
    if (m_darkenReady && m_darken > 0.0f) {
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_CULL_FACE);
        glEnable(GL_BLEND);
        // Use separate blend for alpha: keep dst alpha intact (GL_ZERO, GL_ONE)
        // so the FBO remains fully opaque for Qt Quick's premultiplied compositing.
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA,
                            GL_ZERO, GL_ONE);
        glUseProgram(m_darkenProg);
        glUniform1f(m_darkenAlphaLoc, m_darken);
        glBindVertexArray(m_darkenVao);
        glDrawArrays(GL_TRIANGLES, 0, 6);
        glBindVertexArray(0);
        glUseProgram(0);
        glDisable(GL_BLEND);
    }

    // Schedule the next frame only while running; when stopped, the render
    // loop goes idle and is restarted by ProjectMItem::setRunning(true).
    if (m_running)
        update();
}

// ============================================================
// Shared audio capture — one instance feeds all ProjectMItems
//
// Lock ordering (always acquire outer before inner to avoid deadlock):
//   s_audioMutex  >  AudioBroadcast::mtx  >  PcmAccum::mtx
// The AudioCapture thread only ever holds the inner two locks.
// ============================================================
static std::mutex s_audioMutex;
static AudioCapture *s_audioCapture = nullptr;
static std::shared_ptr<AudioBroadcast> s_audioBroadcast;
static QMetaObject::Connection s_quitConn; // guards against duplicate aboutToQuit connections

// ============================================================
// ProjectMItem — QML item
// ============================================================
ProjectMItem::ProjectMItem(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
    , m_pcmAccum(std::make_shared<PcmAccum>())
{
    setMirrorVertically(true);
    setTextureFollowsItemSize(true);

    m_presetTimer = new QTimer(this);
    m_presetTimer->setSingleShot(false);
    connect(m_presetTimer, &QTimer::timeout,
            this, &ProjectMItem::onPresetTimer);

    setupDbus();
}

ProjectMItem::~ProjectMItem()
{
    // Explicitly remove the D-Bus match rule.  QObject destruction disconnects
    // Qt signal/slot connections, but QDBusConnection match rules are reference-
    // counted by the bus daemon independently of QObject lifetime — failing to
    // disconnect leaks the rule in the daemon across repeated item creation.
    QDBusConnection::sessionBus().disconnect(
        QString(), QString(),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onDbusPropertiesChanged(QString, QVariantMap, QStringList)));

    // Call stopAudio() unconditionally: setRunning(false) is a no-op when
    // m_running is already false, which would silently skip unsubscribing.
    stopAudio();
    m_presetTimer->stop();
}

// ---- setupDbus ------------------------------------------------------------
void ProjectMItem::setupDbus()
{
    QDBusConnection session = QDBusConnection::sessionBus();
    bool ok = session.connect(
        QString(),                               // any service
        QString(),                               // any path
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"),
        this,
        SLOT(onDbusPropertiesChanged(QString, QVariantMap, QStringList)));
    if (!ok)
        qCWarning(lcPM) << "D-Bus MPRIS match failed — MPRIS preset advance disabled";
}

// ---- property setters -----------------------------------------------------
void ProjectMItem::setPresetsDir(const QString &dir)
{
    if (m_presetsDir == dir) return;
    m_presetsDir = dir;
    emit presetsDirChanged();
    scanPresets();
}

void ProjectMItem::setDarken(float v)
{
    if (qFuzzyCompare(m_darken, v)) return;
    m_darken = v;
    emit darkenChanged();
    update();
}

void ProjectMItem::setMeshWidth(int v)
{
    if (m_meshWidth == v) return;
    m_meshWidth = v;
    emit meshWidthChanged();
}

void ProjectMItem::setMeshHeight(int v)
{
    if (m_meshHeight == v) return;
    m_meshHeight = v;
    emit meshHeightChanged();
}

void ProjectMItem::setFps(int v)
{
    if (m_fps == v) return;
    m_fps = v;
    emit fpsChanged();
}

// Clamp preset interval to [1 s, 24 h] before converting to int ms.
static int intervalMs(double secs)
{
    return static_cast<int>(qBound(1.0, secs, 86400.0) * 1000.0);
}

void ProjectMItem::setPresetInterval(double v)
{
    if (qFuzzyCompare(m_presetInterval, v)) return;
    m_presetInterval = v;
    emit presetIntervalChanged();
    if (m_running && m_presetTimer->isActive())
        m_presetTimer->setInterval(intervalMs(v));
}

void ProjectMItem::setRunning(bool v)
{
    if (m_running == v) return;
    m_running = v;
    emit runningChanged();
    if (v) {
        // Discard PCM that accumulated while stopped — feeding it all at once
        // to projectM on the first rendered frame would cause a visual glitch.
        {
            std::lock_guard<std::mutex> lk(m_pcmAccum->mtx);
            m_pcmAccum->samples.clear();
        }
        startAudio();
        if (m_autoPresets)
            m_presetTimer->start(intervalMs(m_presetInterval));
        // Re-kick the render loop; it went idle when running was false.
        update();
    } else {
        m_presetTimer->stop();
        stopAudio();
    }
}

void ProjectMItem::setAudioSource(const QString &src)
{
    if (m_audioSource == src) return;
    m_audioSource = src;
    emit audioSourceChanged();
    // Restart audio with new source if currently running.
    // Clear the PCM buffer between the two to avoid feeding old-source audio
    // to projectM on the first frame after the switch.
    if (m_running) {
        stopAudio();
        {
            std::lock_guard<std::mutex> lk(m_pcmAccum->mtx);
            m_pcmAccum->samples.clear();
        }
        startAudio();
    }
}

void ProjectMItem::setAutoPresets(bool v)
{
    if (m_autoPresets == v) return;
    m_autoPresets = v;
    emit autoPresetsChanged();
    if (m_running) {
        if (v)
            m_presetTimer->start(intervalMs(m_presetInterval));
        else
            m_presetTimer->stop();
    }
}

// ---- createRenderer -------------------------------------------------------
QQuickFramebufferObject::Renderer *ProjectMItem::createRenderer() const
{
    return new ProjectMRenderer();
}

// ---- consumePreset --------------------------------------------------------
QString ProjectMItem::consumePreset()
{
    QMutexLocker lk(&m_presetMutex);
    QString p = m_pendingPreset;
    m_pendingPreset.clear();
    return p;
}

// ---- requestPreset --------------------------------------------------------
void ProjectMItem::requestPreset(const QString &path)
{
    {
        QMutexLocker lk(&m_presetMutex);
        m_pendingPreset = path;
    }
    update();
}

// ---- scanPresets ----------------------------------------------------------
void ProjectMItem::scanPresets()
{
    m_presets.clear();
    if (m_presetsDir.isEmpty()) return;

    namespace fs = std::filesystem;
    std::error_code ec;
    fs::path root(m_presetsDir.toStdString());
    // Resolve symlinks (same as waylivepaper's realpath call)
    fs::path resolved = fs::canonical(root, ec);
    if (ec) {
        qCWarning(lcPM) << "scanPresets: cannot resolve" << m_presetsDir << ":" << ec.message().c_str();
        resolved = root;
    }

    try {
        for (auto const &entry :
             fs::recursive_directory_iterator(resolved, ec)) {
            std::error_code entry_ec;
            if (!entry.is_regular_file(entry_ec)) continue; // non-throwing; skips unreadable entries
            auto ext = entry.path().extension().string();
            if (ext == ".milk" || ext == ".prjm")
                m_presets.append(QString::fromStdString(entry.path().string()));
        }
    } catch (const fs::filesystem_error &e) {
        qCWarning(lcPM) << "scanPresets: filesystem error during iteration:"
                        << e.what();
    }
    if (ec)
        qCWarning(lcPM) << "scanPresets iteration error:" << ec.message().c_str();

    qCDebug(lcPM) << "scanned" << m_presets.size() << "presets from" << m_presetsDir;

    // Shuffle list so rotation is random from the start.
    // Wrap QRandomGenerator in a UniformRandomBitGenerator adapter.
    struct QRngAdapter {
        using result_type = quint32;
        static constexpr result_type min() { return 0; }
        static constexpr result_type max() { return std::numeric_limits<quint32>::max(); }
        result_type operator()() { return QRandomGenerator::global()->generate(); }
    };
    std::shuffle(m_presets.begin(), m_presets.end(), QRngAdapter{});

    // Immediately show first preset if running
    if (!m_presets.isEmpty())
        advancePreset();
}

// ---- advancePreset --------------------------------------------------------
void ProjectMItem::advancePreset()
{
    if (m_presets.isEmpty()) return;
    int idx = static_cast<int>(
        QRandomGenerator::global()->bounded(static_cast<quint32>(m_presets.size())));
    QString next = m_presets.at(idx);
    {
        QMutexLocker lk(&m_presetMutex);
        m_pendingPreset = next;
    }
    update();
}

// ---- timer slot -----------------------------------------------------------
void ProjectMItem::onPresetTimer()
{
    if (!m_autoPresets) return;
    advancePreset();
}

// ---- D-Bus slot -----------------------------------------------------------
void ProjectMItem::onDbusPropertiesChanged(const QString &iface,
                                           const QVariantMap &changed,
                                           const QStringList & /*invalidated*/)
{
    if (!m_autoPresets) return;  // preset managed externally by ProjectMService
    if (iface != QLatin1String("org.mpris.MediaPlayer2.Player")) return;
    if (!changed.contains(QStringLiteral("Metadata"))) return;

    qCDebug(lcPM) << "MPRIS: track changed — advancing preset";
    advancePreset();
    // Restart rotation timer so interval resets from now
    if (m_running && m_presetTimer->isActive())
        m_presetTimer->start(intervalMs(m_presetInterval));
}

// ---- audio lifecycle ------------------------------------------------------
void ProjectMItem::startAudio()
{
    std::lock_guard<std::mutex> lk(s_audioMutex);
    if (!s_audioBroadcast)
        s_audioBroadcast = std::make_shared<AudioBroadcast>();
    {
        std::lock_guard<std::mutex> blk(s_audioBroadcast->mtx);
        // Prune any dead entries before adding ours, so the subscriber list
        // doesn't accumulate stale weak_ptrs from items that leaked stopAudio().
        auto &subs = s_audioBroadcast->subscribers;
        subs.erase(
            std::remove_if(subs.begin(), subs.end(),
                [](const std::weak_ptr<PcmAccum> &wp) { return wp.expired(); }),
            subs.end());
        subs.push_back(m_pcmAccum);
    }
    m_audioSubscribed = true;
    if (!s_audioCapture) {
        qCDebug(lcPM) << "audio: starting shared capture, source:"
                      << (m_audioSource.isEmpty() ? "<auto>" : m_audioSource);
        s_audioCapture = new AudioCapture(s_audioBroadcast, m_audioSource, nullptr);
        s_audioCapture->start();

        // Ensure the capture thread is joined on exit (once only — avoid
        // duplicate connections which would fire the lambda multiple times).
        if (!s_quitConn) {
            if (auto *app = QCoreApplication::instance()) {
                s_quitConn = QObject::connect(app, &QCoreApplication::aboutToQuit,
                                              app, []() {
                    // Take ownership under the lock, then release before
                    // blocking on wait() to avoid a potential deadlock if
                    // stopAudio() is also running on the main thread.
                    AudioCapture *cap = nullptr;
                    {
                        std::lock_guard<std::mutex> lk2(s_audioMutex);
                        cap = s_audioCapture;
                        s_audioCapture = nullptr;
                        s_audioBroadcast.reset();
                    }
                    if (cap) {
                        qCDebug(lcPM) << "audio: joining capture on app quit";
                        cap->requestStop();
                        cap->wait(); // no lock held here
                        delete cap;
                    }
                }, Qt::DirectConnection);

                // QMetaObject::Connection::operator bool() returns true even
                // after the connection is severed (e.g. when QCoreApplication
                // is destroyed), so the `if (!s_quitConn)` guard above would
                // never re-register for a new QCoreApplication (unit tests).
                // Resetting s_quitConn on app destruction fixes this.
                QObject::connect(app, &QObject::destroyed, []() {
                    s_quitConn = {};
                });
            }
        }
    } else {
        if (!m_audioSource.isEmpty()) {
            qCWarning(lcPM) << "audio: audioSource" << m_audioSource
                            << "ignored — shared capture already running;"
                               " only the first item's source is used";
        }
        qCDebug(lcPM) << "audio: subscribing to existing shared capture";
    }
}

void ProjectMItem::stopAudio()
{
    // Guard against double-calls (destructor + setRunning(false) both invoke this).
    if (!m_audioSubscribed) return;
    m_audioSubscribed = false;

    // Take ownership of the capture pointer under the lock, clear statics,
    // then release the lock before calling wait() — blocking with the mutex
    // held could deadlock if aboutToQuit fires on the same thread.
    AudioCapture *cap = nullptr;
    {
        std::lock_guard<std::mutex> lk(s_audioMutex);
        if (!s_audioBroadcast) return;
        {
            std::lock_guard<std::mutex> blk(s_audioBroadcast->mtx);
            auto &subs = s_audioBroadcast->subscribers;
            // Remove this item's own accum.  Also purge any other expired
            // weak_ptrs as a safety net for items destroyed abnormally.
            subs.erase(
                std::remove_if(subs.begin(), subs.end(),
                    [this](const std::weak_ptr<PcmAccum> &wp) {
                        auto p = wp.lock();
                        return !p || p == m_pcmAccum;
                    }),
                subs.end());
            qCDebug(lcPM) << "audio: unsubscribed," << subs.size() << "remaining";
            if (!subs.empty()) return;
        }
        // Last subscriber — take ownership, clear statics before releasing lock
        qCDebug(lcPM) << "audio: stopping shared capture (no subscribers)";
        cap = s_audioCapture;
        s_audioCapture = nullptr;
        s_audioBroadcast.reset();
    }
    // Join the thread with no lock held.
    // cap can be null if s_audioCapture was already cleared (e.g. aboutToQuit
    // fired concurrently, or new AudioCapture() threw during startAudio()).
    if (cap) {
        cap->requestStop();
        cap->wait();
        delete cap;
    }
}

// MOC for classes defined in .cpp
#include "ProjectMItem.moc"
