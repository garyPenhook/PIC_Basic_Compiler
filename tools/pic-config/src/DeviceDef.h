#pragma once
#include <QString>
#include <QVector>
#include <QtGlobal>

// One selectable value of a configuration setting. `value` is already in
// register position (i.e. it is compared directly with `mask & word`).
struct ConfigValue {
    quint32 value = 0;
    QString name;
    QString desc;
};

struct ConfigSetting {
    quint32 mask = 0;
    QString name;
    QString desc;
    QVector<ConfigValue> values;
    int defaultIndex = 0;  // index into `values`, from the word's default
};

struct ConfigWord {
    quint32 address = 0;
    quint32 mask = 0;
    quint32 defaultValue = 0;
    QString name;  // CONFIG1L ...
    QVector<ConfigSetting> settings;
};

struct DeviceDef {
    QString name;  // PIC18F27Q10
    QVector<ConfigWord> words;
};

// Parses Microchip's `<device>.cfgdata` (CWORD / CSETTING / CVALUE records,
// as shipped in the MPLAB XC8 pack). Words without settings (IDLOCn) are
// dropped. Returns false and fills `error` on failure.
bool parseCfgData(const QString &text, const QString &fallbackName, DeviceDef &out, QString &error);
