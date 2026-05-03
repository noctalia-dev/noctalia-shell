#pragma once

#include <QMutex>
#include <QOpenGLFramebufferObject>
#include <QQuickFramebufferObject>
#include <QStringList>
#include <QTimer>

#include <memory>
#include <mutex>
#include <vector>

// ---------------------------------------------------------------------------
// PcmAccum — shared PCM ring between AudioCapture and ProjectMRenderer
// ---------------------------------------------------------------------------
struct PcmAccum {
    std::mutex mtx;
    std::vector<float> samples; // interleaved stereo float32, capped at PCM_MAX_SAMPLES
};

// ---------------------------------------------------------------------------
// Forward declarations
// ---------------------------------------------------------------------------
class AudioCapture;

// ---------------------------------------------------------------------------
// ProjectMItem — QQuickFramebufferObject exposed as QML type ProjectMItem
//                registered under URI  qs.Multimedia  (version 1.0)
// ---------------------------------------------------------------------------
class ProjectMItem : public QQuickFramebufferObject {
    Q_OBJECT

    // ---- QML properties ---------------------------------------------------
    Q_PROPERTY(QString presetsDir READ presetsDir WRITE setPresetsDir
                   NOTIFY presetsDirChanged)
    Q_PROPERTY(float darken READ darken WRITE setDarken NOTIFY darkenChanged)
    Q_PROPERTY(int meshWidth READ meshWidth WRITE setMeshWidth
                   NOTIFY meshWidthChanged)
    Q_PROPERTY(int meshHeight READ meshHeight WRITE setMeshHeight
                   NOTIFY meshHeightChanged)
    Q_PROPERTY(int fps READ fps WRITE setFps NOTIFY fpsChanged)
    Q_PROPERTY(double presetInterval READ presetInterval WRITE setPresetInterval
                   NOTIFY presetIntervalChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(QString audioSource READ audioSource WRITE setAudioSource
                   NOTIFY audioSourceChanged)
    Q_PROPERTY(bool autoPresets READ autoPresets WRITE setAutoPresets
                   NOTIFY autoPresetsChanged)

public:
    explicit ProjectMItem(QQuickItem *parent = nullptr);
    ~ProjectMItem() override;

    // ---- property accessors -----------------------------------------------
    QString presetsDir() const { return m_presetsDir; }
    float darken() const { return m_darken; }
    int meshWidth() const { return m_meshWidth; }
    int meshHeight() const { return m_meshHeight; }
    int fps() const { return m_fps; }
    double presetInterval() const { return m_presetInterval; }
    bool running() const { return m_running; }
    QString audioSource() const { return m_audioSource; }
    bool autoPresets() const { return m_autoPresets; }

    void setPresetsDir(const QString &dir);
    void setDarken(float v);
    void setMeshWidth(int v);
    void setMeshHeight(int v);
    void setFps(int v);
    void setPresetInterval(double v);
    void setRunning(bool v);
    void setAudioSource(const QString &src);
    void setAutoPresets(bool v);

    // ---- renderer interface -----------------------------------------------
    Renderer *createRenderer() const override;

    // Called by ProjectMRenderer::synchronize() — render thread, main blocked
    QString consumePreset();

    // Externally push a specific preset (bypasses internal rotation).
    Q_INVOKABLE void requestPreset(const QString &path);
    std::shared_ptr<PcmAccum> pcmAccum() const { return m_pcmAccum; }

signals:
    void presetsDirChanged();
    void darkenChanged();
    void meshWidthChanged();
    void meshHeightChanged();
    void fpsChanged();
    void presetIntervalChanged();
    void runningChanged();
    void audioSourceChanged();
    void autoPresetsChanged();

private slots:
    void onPresetTimer();
    void onDbusPropertiesChanged(const QString &iface,
                                 const QVariantMap &changed,
                                 const QStringList &invalidated);

private:
    void scanPresets();
    void advancePreset();
    void startAudio();
    void stopAudio();
    void setupDbus();

    // ---- state ------------------------------------------------------------
    QString m_presetsDir;
    float m_darken = 0.7f;
    int m_meshWidth = 24;
    int m_meshHeight = 18;
    int m_fps = 30;
    double m_presetInterval = 120.0;
    bool m_running = false;
    QString m_audioSource;
    bool m_autoPresets = true;

    QStringList m_presets;

    // Pending preset path: written by main thread, consumed by render thread
    // inside synchronize().  Protected by m_presetMutex.
    mutable QMutex m_presetMutex;
    QString m_pendingPreset;

    std::shared_ptr<PcmAccum> m_pcmAccum;
    bool m_audioSubscribed = false; // true while m_pcmAccum is in s_audioBroadcast

    QTimer *m_presetTimer = nullptr;
};
