#pragma once
#include "DeviceDef.h"

#include <QString>
#include <QVector>

// Output dialects. Add a new one by extending this enum, formatName() and
// the switch in formatConfig().
enum class OutputFormat {
    Basic,       // Config A = X, B = Y, ...   (basil style)
    XC8Pragma,   // #pragma config A = X
};

// `clockMhz` (Basic only, empty = off) adds the `Device`/`Clock` lines before the Config and
// `Include "intosc"` after it, so the whole block pastes as a program header.
QString formatName(OutputFormat f);

// `selection[w][s]` is the chosen value index for settings s of word w.
using Selection = QVector<QVector<int>>;

QString formatConfig(const DeviceDef &dev, const Selection &selection, OutputFormat fmt,
                     bool onlyChanged, bool withComments,
                     const QString &clockMhz = QString());
