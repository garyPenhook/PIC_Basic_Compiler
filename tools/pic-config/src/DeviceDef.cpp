#include "DeviceDef.h"

#include <QRegularExpression>
#include <QStringList>

bool parseCfgData(const QString &text, const QString &fallbackName, DeviceDef &out, QString &error)
{
    out = DeviceDef{};
    out.name = fallbackName;

    static const QRegularExpression nameRe(
        QStringLiteral(R"(^#\s*Microchip\s+(\S+)\s+Configuration Word Definitions)"));

    const QStringList lines = text.split('\n');
    int lineNo = 0;
    for (QString line : lines) {
        ++lineNo;
        line = line.trimmed();
        if (line.isEmpty())
            continue;
        if (line.startsWith('#')) {
            const auto m = nameRe.match(line);
            if (m.hasMatch())
                out.name = m.captured(1);
            continue;
        }

        auto fail = [&](const QString &why) {
            error = QStringLiteral("line %1: %2").arg(lineNo).arg(why);
            return false;
        };
        bool ok = false;

        if (line.startsWith(QLatin1String("CWORD:"))) {
            const QStringList f = line.split(':');
            if (f.size() < 5)
                return fail(QStringLiteral("bad CWORD"));
            ConfigWord w;
            w.address = f[1].toUInt(&ok, 16);
            if (!ok) return fail(QStringLiteral("bad CWORD address"));
            w.mask = f[2].toUInt(&ok, 16);
            if (!ok) return fail(QStringLiteral("bad CWORD mask"));
            w.defaultValue = f[3].toUInt(&ok, 16);
            if (!ok) return fail(QStringLiteral("bad CWORD default"));
            w.name = f[4].split(',').first();
            out.words.push_back(w);
        } else if (line.startsWith(QLatin1String("CSETTING:"))) {
            if (out.words.isEmpty())
                return fail(QStringLiteral("CSETTING before CWORD"));
            const QStringList f = line.split(':');
            if (f.size() < 3)
                return fail(QStringLiteral("bad CSETTING"));
            ConfigSetting s;
            s.mask = f[1].toUInt(&ok, 16);
            if (!ok) return fail(QStringLiteral("bad CSETTING mask"));
            s.name = f[2].split(',').first();
            s.desc = f.mid(3).join(':');
            out.words.last().settings.push_back(s);
        } else if (line.startsWith(QLatin1String("CVALUE:"))) {
            if (out.words.isEmpty() || out.words.last().settings.isEmpty())
                return fail(QStringLiteral("CVALUE before CSETTING"));
            const QStringList f = line.split(':');
            if (f.size() < 3)
                return fail(QStringLiteral("bad CVALUE"));
            ConfigValue v;
            v.value = f[1].toUInt(&ok, 16);
            if (!ok) return fail(QStringLiteral("bad CVALUE value"));
            v.name = f[2].split(',').first();
            v.desc = f.mid(3).join(':');
            out.words.last().settings.last().values.push_back(v);
        }
        // CMSG and anything else: not needed.
    }

    // Drop settings-less words (IDLOCn, CONFIG5H) and resolve defaults.
    QVector<ConfigWord> kept;
    for (ConfigWord &w : out.words) {
        if (w.settings.isEmpty())
            continue;
        for (ConfigSetting &s : w.settings) {
            if (s.values.isEmpty()) {
                error = QStringLiteral("%1.%2 has no values").arg(w.name, s.name);
                return false;
            }
            const quint32 def = w.defaultValue & s.mask;
            for (int i = 0; i < s.values.size(); ++i)
                if (s.values[i].value == def) {
                    s.defaultIndex = i;
                    break;
                }
        }
        kept.push_back(w);
    }
    out.words = kept;

    if (out.words.isEmpty()) {
        error = QStringLiteral("no configuration settings found");
        return false;
    }
    return true;
}
