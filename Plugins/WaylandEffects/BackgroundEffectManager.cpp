#include "BackgroundEffectManager.h"

BackgroundEffectManager::BackgroundEffectManager()
    : QWaylandClientExtensionTemplate(/* version */ 1)
{
    initialize();
}

BackgroundEffectManager *BackgroundEffectManager::instance()
{
    static auto *mgr = new BackgroundEffectManager;
    return mgr;
}

void BackgroundEffectManager::ext_background_effect_manager_v1_capabilities(uint32_t capabilities)
{
    const bool blur = capabilities & capability_blur;
    if (m_hasBlur != blur) {
        m_hasBlur = blur;
        Q_EMIT blurSupportChanged();
    }
}
