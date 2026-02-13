#pragma once

#include <QQuickItem>
#include "qwayland-ext-background-effect-v1.h"

class BackgroundBlur : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT

    /// List of rectangles (in surface-local coordinates) to blur.
    /// An empty list removes the blur effect.
    Q_PROPERTY(QList<QRectF> regions READ regions WRITE setRegions NOTIFY regionsChanged)

    /// Whether the blur effect is currently active on the surface.
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit BackgroundBlur(QQuickItem *parent = nullptr);
    ~BackgroundBlur() override;

    QList<QRectF> regions() const { return m_regions; }
    void setRegions(const QList<QRectF> &regions);

    bool active() const { return m_effect != nullptr; }

Q_SIGNALS:
    void regionsChanged();
    void activeChanged();

protected:
    void componentComplete() override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;

private:
    void tryAttach();
    void detach();
    void updateBlurRegion();

    struct wl_surface *nativeSurface();
    struct wl_compositor *nativeCompositor();

    QList<QRectF> m_regions;
    QtWayland::ext_background_effect_surface_v1 *m_effect = nullptr;
    QMetaObject::Connection m_windowVisibleConn;
    QMetaObject::Connection m_managerActiveConn;
};
