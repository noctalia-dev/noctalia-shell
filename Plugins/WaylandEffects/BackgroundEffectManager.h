#pragma once

#include <QtWaylandClient/QWaylandClientExtensionTemplate>
#include "qwayland-ext-background-effect-v1.h"

class BackgroundEffectManager
    : public QWaylandClientExtensionTemplate<BackgroundEffectManager>
    , public QtWayland::ext_background_effect_manager_v1
{
    Q_OBJECT

public:
    static BackgroundEffectManager *instance();

    bool hasBlur() const { return m_hasBlur; }

Q_SIGNALS:
    void blurSupportChanged();

protected:
    void ext_background_effect_manager_v1_capabilities(uint32_t capabilities) override;

private:
    explicit BackgroundEffectManager();

    bool m_hasBlur = false;
};
