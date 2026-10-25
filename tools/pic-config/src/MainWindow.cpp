#include "MainWindow.h"

#include <QApplication>
#include <QCheckBox>
#include <QClipboard>
#include <QComboBox>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFontDatabase>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QScrollArea>
#include <QSplitter>
#include <QStatusBar>
#include <QToolButton>
#include <QVBoxLayout>

namespace {
QString fallbackFromFile(const QString &fileName)
{
    // 18f27q10.cfgdata -> PIC18F27Q10
    return QStringLiteral("PIC") + QFileInfo(fileName).completeBaseName().toUpper();
}
}  // namespace

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent)
{
    setWindowTitle(QStringLiteral("PIC Config Helper"));
    resize(1100, 720);

    auto *central = new QWidget;
    auto *root = new QVBoxLayout(central);

    // --- top bar -----------------------------------------------------
    auto *bar = new QHBoxLayout;
    deviceBox_ = new QComboBox;
    formatBox_ = new QComboBox;
    formatBox_->addItem(formatName(OutputFormat::Basic), int(OutputFormat::Basic));
    formatBox_->addItem(formatName(OutputFormat::XC8Pragma), int(OutputFormat::XC8Pragma));
    onlyChanged_ = new QCheckBox(tr("Only settings changed from default"));
    comments_ = new QCheckBox(tr("Comments"));
    comments_->setChecked(true);
    onlyChanged_->setChecked(true);
    clockBox_ = new QComboBox;
    clockBox_->setToolTip(tr("Adds Device, Clock and Include \"intosc\" lines so the output is a complete header"));
    clockBox_->addItem(tr("none"), QString());
    for (const char *mhz : {"64", "48", "32", "16", "12", "8", "4", "2", "1"})
        clockBox_->addItem(QString::fromLatin1(mhz) + QStringLiteral(" MHz"), QString::fromLatin1(mhz));
    auto *openBtn = new QPushButton(tr("Add device file…"));
    resetBtn_ = new QPushButton(tr("Clear all changes"));
    resetBtn_->setToolTip(tr("Put every setting back to its default"));
    resetBtn_->setEnabled(false);
    bar->addWidget(new QLabel(tr("Device:")));
    bar->addWidget(deviceBox_);
    bar->addSpacing(12);
    bar->addWidget(new QLabel(tr("Output:")));
    bar->addWidget(formatBox_);
    bar->addSpacing(12);
    bar->addWidget(new QLabel(tr("Clock:")));
    bar->addWidget(clockBox_);
    bar->addSpacing(12);
    bar->addWidget(onlyChanged_);
    bar->addWidget(comments_);
    bar->addStretch();
    bar->addWidget(openBtn);
    bar->addWidget(resetBtn_);
    root->addLayout(bar);

    // --- body --------------------------------------------------------
    auto *split = new QSplitter;
    auto *scroll = new QScrollArea;
    scroll->setWidgetResizable(true);
    settingsHost_ = new QWidget;
    settingsLayout_ = new QVBoxLayout(settingsHost_);
    scroll->setWidget(settingsHost_);
    split->addWidget(scroll);

    auto *right = new QWidget;
    auto *rl = new QVBoxLayout(right);
    rl->setContentsMargins(0, 0, 0, 0);
    output_ = new QPlainTextEdit;
    output_->setReadOnly(true);
    output_->setLineWrapMode(QPlainTextEdit::NoWrap);
    output_->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    auto *copyBtn = new QPushButton(tr("Copy to clipboard"));
    wordsInfo_ = new QLabel;
    wordsInfo_->setTextInteractionFlags(Qt::TextSelectableByMouse);
    wordsInfo_->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    rl->addWidget(new QLabel(tr("Paste into your source file:")));
    rl->addWidget(output_, 1);
    rl->addWidget(copyBtn);
    rl->addWidget(wordsInfo_);
    split->addWidget(right);
    split->setStretchFactor(0, 3);
    split->setStretchFactor(1, 2);
    root->addWidget(split, 1);
    setCentralWidget(central);

    connect(deviceBox_, &QComboBox::currentIndexChanged, this, &MainWindow::deviceChanged);
    connect(formatBox_, &QComboBox::currentIndexChanged, this, &MainWindow::refreshOutput);
    connect(clockBox_, &QComboBox::currentIndexChanged, this, &MainWindow::refreshOutput);
    connect(onlyChanged_, &QCheckBox::toggled, this, &MainWindow::refreshOutput);
    connect(comments_, &QCheckBox::toggled, this, &MainWindow::refreshOutput);
    connect(openBtn, &QPushButton::clicked, this, &MainWindow::openDeviceFile);
    connect(resetBtn_, &QPushButton::clicked, this, &MainWindow::resetToDefaults);
    connect(copyBtn, &QPushButton::clicked, this, &MainWindow::copyOutput);

    loadBuiltInDevices();
    if (deviceBox_->count() > 0)
        deviceChanged(deviceBox_->currentIndex());
}

bool MainWindow::addDevice(const QString &text, const QString &fallbackName, const QString &origin)
{
    DeviceDef dev;
    QString err;
    if (!parseCfgData(text, fallbackName, dev, err)) {
        QMessageBox::warning(this, tr("Device file"), tr("%1: %2").arg(origin, err));
        return false;
    }
    // Re-adding a loaded device replaces its definition in place, and the
    // combo would not emit a change (same index), so the panel must be
    // rebuilt explicitly rather than via the signal.
    const bool isNew = !devices_.contains(dev.name);
    {
        QSignalBlocker block(deviceBox_);
        devices_.insert(dev.name, dev);
        if (isNew)
            deviceBox_->addItem(dev.name);
        deviceBox_->setCurrentText(dev.name);
    }
    deviceChanged(deviceBox_->currentIndex());
    return true;
}

void MainWindow::loadBuiltInDevices()
{
    const QDir dir(QStringLiteral(":/devices"));
    for (const QString &f : dir.entryList({QStringLiteral("*.cfgdata")}, QDir::Files, QDir::Name)) {
        QFile file(dir.filePath(f));
        if (file.open(QIODevice::ReadOnly | QIODevice::Text))
            addDevice(QString::fromUtf8(file.readAll()), fallbackFromFile(f), f);
    }
    // Prefer the first device alphabetically as the initial selection.
    if (deviceBox_->count() > 0)
        deviceBox_->setCurrentIndex(0);
}

void MainWindow::openDeviceFile()
{
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Add device file"), QString(), tr("Microchip cfgdata (*.cfgdata);;All files (*)"));
    if (path.isEmpty())
        return;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QMessageBox::warning(this, tr("Device file"), tr("Cannot read %1").arg(path));
        return;
    }
    addDevice(QString::fromUtf8(file.readAll()), fallbackFromFile(path), path);
}

void MainWindow::deviceChanged(int)
{
    const auto it = devices_.constFind(deviceBox_->currentText());
    current_ = (it == devices_.constEnd()) ? nullptr : &it.value();
    buildSettingsPanel();
    refreshOutput();
}

void MainWindow::buildSettingsPanel()
{
    // Remove the old panel (combos_ is cleared first so refreshOutput can
    // never see dangling pointers).
    combos_.clear();
    reverts_.clear();
    labels_.clear();
    while (QLayoutItem *item = settingsLayout_->takeAt(0)) {
        delete item->widget();
        delete item;
    }
    if (!current_)
        return;

    combos_.resize(current_->words.size());
    reverts_.resize(current_->words.size());
    labels_.resize(current_->words.size());
    for (int w = 0; w < current_->words.size(); ++w) {
        const ConfigWord &word = current_->words[w];
        auto *box = new QGroupBox(QStringLiteral("%1   (0x%2)")
                                      .arg(word.name)
                                      .arg(word.address, 6, 16, QLatin1Char('0')).toUpper());
        auto *form = new QFormLayout(box);
        for (int s = 0; s < word.settings.size(); ++s) {
            const ConfigSetting &set = word.settings[s];
            auto *combo = new QComboBox;
            for (const ConfigValue &v : set.values) {
                combo->addItem(QStringLiteral("%1  —  %2").arg(v.name, v.desc));
                combo->setItemData(combo->count() - 1, v.desc, Qt::ToolTipRole);
            }
            combo->setCurrentIndex(set.defaultIndex);
            combo->setToolTip(set.desc);
            combo->setSizeAdjustPolicy(QComboBox::AdjustToMinimumContentsLengthWithIcon);
            combo->setMinimumContentsLength(24);
            auto *label = new QLabel(set.name);
            label->setToolTip(set.desc);
            auto *revert = new QToolButton;
            revert->setText(QStringLiteral("↺"));
            revert->setToolTip(tr("Back to the default for %1").arg(set.name));
            revert->setAutoRaise(true);
            // Keeps its space while hidden so the combos do not shift when a setting changes.
            auto sp = revert->sizePolicy();
            sp.setRetainSizeWhenHidden(true);
            revert->setSizePolicy(sp);
            revert->setVisible(false);
            auto *row = new QHBoxLayout;
            row->setContentsMargins(0, 0, 0, 0);
            row->addWidget(combo, 1);
            row->addWidget(revert);
            form->addRow(label, row);
            combos_[w].push_back(combo);
            reverts_[w].push_back(revert);
            labels_[w].push_back(label);
            connect(combo, &QComboBox::currentIndexChanged, this, &MainWindow::refreshOutput);
            connect(revert, &QToolButton::clicked, this, [combo, d = set.defaultIndex] { combo->setCurrentIndex(d); });
        }
        settingsLayout_->addWidget(box);
    }
    settingsLayout_->addStretch();
}

void MainWindow::resetToDefaults()
{
    if (!current_)
        return;
    for (int w = 0; w < combos_.size(); ++w)
        for (int s = 0; s < combos_[w].size(); ++s) {
            QSignalBlocker block(combos_[w][s]);
            combos_[w][s]->setCurrentIndex(current_->words[w].settings[s].defaultIndex);
        }
    refreshOutput();
}

void MainWindow::refreshOutput()
{
    bool consistent = current_ && combos_.size() == current_->words.size();
    for (int w = 0; consistent && w < combos_.size(); ++w)
        consistent = combos_[w].size() == current_->words[w].settings.size();
    if (!consistent) {
        output_->clear();
        wordsInfo_->clear();
        resetBtn_->setEnabled(false);
        return;
    }
    // Mark what differs from the default and offer a way back for each.
    bool anyChanged = false;
    for (int w = 0; w < combos_.size(); ++w)
        for (int s = 0; s < combos_[w].size(); ++s) {
            const bool changed = combos_[w][s]->currentIndex() != current_->words[w].settings[s].defaultIndex;
            anyChanged = anyChanged || changed;
            reverts_[w][s]->setVisible(changed);
            QFont f = labels_[w][s]->font();
            f.setBold(changed);
            labels_[w][s]->setFont(f);
        }
    resetBtn_->setEnabled(anyChanged);

    Selection sel(combos_.size());
    for (int w = 0; w < combos_.size(); ++w)
        for (QComboBox *c : combos_[w])
            sel[w].push_back(c->currentIndex());

    const auto fmt = OutputFormat(formatBox_->currentData().toInt());
    output_->setPlainText(formatConfig(*current_, sel, fmt, onlyChanged_->isChecked(), comments_->isChecked(),
                                    clockBox_->currentData().toString()));

    // Resulting configuration bytes, for cross-checking against a programmer.
    QStringList bytes;
    for (int w = 0; w < current_->words.size(); ++w) {
        const ConfigWord &word = current_->words[w];
        quint32 value = word.defaultValue;
        for (int s = 0; s < word.settings.size(); ++s) {
            const ConfigSetting &set = word.settings[s];
            value = (value & ~set.mask) | set.values[sel[w][s]].value;
        }
        bytes << QStringLiteral("%1 @0x%2 = 0x%3")
                     .arg(word.name, -9)
                     .arg(word.address, 6, 16, QLatin1Char('0'))
                     .arg(value & 0xFF, 2, 16, QLatin1Char('0'))
                     .toUpper();
    }
    wordsInfo_->setText(bytes.join('\n'));
}

void MainWindow::copyOutput()
{
    QApplication::clipboard()->setText(output_->toPlainText());
    statusBar()->showMessage(tr("Copied"), 2000);
}
