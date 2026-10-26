#include "OutputFormatter.h"

QString formatName(OutputFormat f)
{
    switch (f) {
    case OutputFormat::Basic: return QStringLiteral("BASIC  (Config NAME = VALUE)");
    case OutputFormat::XC8Pragma: return QStringLiteral("XC8 C  (#pragma config)");
    }
    return {};
}

QString formatConfig(const DeviceDef &dev, const Selection &sel, OutputFormat fmt,
                     bool onlyChanged, bool withComments, const QString &clockMhz)
{
    struct Item { QString name, value, comment; bool changed; };
    QVector<Item> items;

    for (int w = 0; w < dev.words.size(); ++w) {
        const ConfigWord &word = dev.words[w];
        for (int s = 0; s < word.settings.size(); ++s) {
            const ConfigSetting &set = word.settings[s];
            const int idx = (w < sel.size() && s < sel[w].size()) ? sel[w][s] : set.defaultIndex;
            if (onlyChanged && idx == set.defaultIndex)
                continue;
            const ConfigValue &v = set.values[idx];
            items.push_back({set.name, v.name, v.desc, idx != set.defaultIndex});
        }
    }

    // intosc.bas: CSWEN = ON is needed for every speed except the one RSTOSC already gives.
    QString warning;
    if (fmt == OutputFormat::Basic && !clockMhz.isEmpty()) {
        QString rstosc, cswen;
        for (int w = 0; w < dev.words.size(); ++w)
            for (int s = 0; s < dev.words[w].settings.size(); ++s) {
                const ConfigSetting &set = dev.words[w].settings[s];
                const int idx = (w < sel.size() && s < sel[w].size()) ? sel[w][s] : set.defaultIndex;
                if (set.name == QLatin1String("RSTOSC")) rstosc = set.values[idx].name;
                else if (set.name == QLatin1String("CSWEN")) cswen = set.values[idx].name;
            }
        // The PIC16F171xx cfgdata spells it "MHz", the PIC18 ones "MHZ".
        const bool startsAtClock = rstosc.compare(QStringLiteral("HFINTOSC_%1MHZ").arg(clockMhz),
                                                  Qt::CaseInsensitive) == 0;
        if (!startsAtClock && cswen != QLatin1String("ON"))
            warning = QStringLiteral("' WARNING: Clock = %1 needs CSWEN = ON for Include \"intosc\"\n")
                          .arg(clockMhz);
    }

    QString out;
    const bool header = fmt == OutputFormat::Basic && !clockMhz.isEmpty();
    if (header) {
        QString part = dev.name;
        if (part.startsWith(QLatin1String("PIC"), Qt::CaseInsensitive))
            part.remove(0, 3);
        out += QStringLiteral("Device = %1\nClock = %2\n").arg(part, clockMhz) + warning + QLatin1Char('\n');
    }
    if (withComments)
        out += QStringLiteral("' %1 configuration\n").arg(dev.name);

    if (items.isEmpty())
        return out + (fmt == OutputFormat::Basic ? QStringLiteral("' (all settings at device defaults)\n")
                                                 : QStringLiteral("// (all settings at device defaults)\n"));

    if (fmt == OutputFormat::Basic) {
        // One Config statement, wrapped with the ' _' line continuation.
        QString line = QStringLiteral("Config ");
        const int wrapAt = 96;
        for (int i = 0; i < items.size(); ++i) {
            const QString part = items[i].name + QStringLiteral(" = ") + items[i].value;
            const bool last = (i == items.size() - 1);
            const QString piece = last ? part : part + QStringLiteral(",");
            if (line.size() + piece.size() + 1 > wrapAt && !line.endsWith(QLatin1String("Config "))) {
                out += line.trimmed() + QStringLiteral(" _\n");
                line = QStringLiteral("       ");
            }
            line += piece + QLatin1Char(' ');
        }
        out += line.trimmed() + QLatin1Char('\n');
        // Per-setting explanations go after the statement: a comment cannot
        // sit inside a ` _` continuation.
        if (withComments) {
            out += QStringLiteral("\n");
            for (const Item &it : items)
                if (it.changed)  // defaults need no explanation
                    out += QStringLiteral("' %1 = %2: %3\n").arg(it.name, it.value, it.comment);
        }
        if (header)
            out += QStringLiteral("\nInclude \"intosc\"\n");
    } else {
        for (const Item &it : items) {
            out += QStringLiteral("#pragma config %1 = %2").arg(it.name, it.value);
            if (withComments && it.changed)
                out += QStringLiteral("  // %1").arg(it.comment);
            out += QLatin1Char('\n');
        }
    }
    return out;
}
