#include <QQmlExtensionPlugin>
#include "ProjectMItem.h"

class NoctaliaMultimediaPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        qmlRegisterType<ProjectMItem>(uri, 1, 0, "ProjectMItem");
    }
};

#include "plugin.moc"
