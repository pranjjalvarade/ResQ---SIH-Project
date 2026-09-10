ResQ - Setup & Installation Guide

Prerequisites & Tools to Install:

Git: Required for cloning and version control (Download: https://git-scm.com/downloads).

Flutter SDK: Ensure Flutter stable channel is installed and the bin directory (e.g. C:\flutter\bin) is added to your system PATH (Installation guide: https://docs.flutter.dev/get-started/install).

Android Studio & Android SDK: Download Android Studio (https://developer.android.com/studio). Through the SDK Manager, ensure Android SDK Platform (API 34/33), Android SDK Command-line Tools, Android SDK Build-Tools, and Android SDK Platform-Tools (adb) are installed.

Java Development Kit: JDK 17 or JDK 21 (bundled with Android Studio under jbr, or installed via OpenJDK).

Hardware & Testing Note:
UI testing works on emulators or Windows desktop. However, testing SOS mesh and signal broadcast via Google Nearby Connections requires at least two physical Android phones with Bluetooth and Location turned ON (emulators lack peer-to-peer radio hardware).

Steps to Run:

Clone repository:
git clone https://github.com/YourUsername/ResQ.git
cd ResQ

Verify environment:
flutter doctor
(Run 'flutter doctor --android-licenses' if prompted)

Install packages:
flutter pub get

Run the app:
flutter run

To manually build the debug APK:
On Windows:
cd android
gradlew.bat assembleDebug

On Mac/Linux:
cd android
./gradlew assembleDebug

The output APK will be at build/app/outputs/flutter-apk/app-debug.apk.

Key Configuration Settings:
In android/gradle.properties, ensure the following lines are set:
org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=1024m
android.useAndroidX=true
android.enableJetifier=false
