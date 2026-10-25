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
                     bool onlyChanged, bool withComments)
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

    QString out;
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
