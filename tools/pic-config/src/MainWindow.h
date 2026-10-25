#pragma once
#include "DeviceDef.h"
#include "OutputFormatter.h"

#include <QMainWindow>
#include <QMap>

class QCheckBox;
class QComboBox;
class QPlainTextEdit;
class QVBoxLayout;
class QWidget;
class QLabel;
class QPushButton;
class QToolButton;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);

private slots:
    void deviceChanged(int index);
    void openDeviceFile();
    void resetToDefaults();
    void copyOutput();
    void refreshOutput();

private:
    void loadBuiltInDevices();
    bool addDevice(const QString &text, const QString &fallbackName, const QString &origin);
    void buildSettingsPanel();

    QMap<QString, DeviceDef> devices_;
    const DeviceDef *current_ = nullptr;
    // combos_[word][setting] mirrors current_->words[word].settings[setting]
    QVector<QVector<QComboBox *>> combos_;
    // Same shape as combos_: the per-setting revert button and the setting's name label.
    QVector<QVector<QToolButton *>> reverts_;
    QVector<QVector<QLabel *>> labels_;

    QPushButton *resetBtn_;
    QComboBox *deviceBox_;
    QComboBox *formatBox_;
    QCheckBox *onlyChanged_;
    QCheckBox *comments_;
    QComboBox *clockBox_;
    QWidget *settingsHost_;
    QVBoxLayout *settingsLayout_;
    QPlainTextEdit *output_;
    QLabel *wordsInfo_;
};
