allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Flutter plugins frequently lag the compileSdk that their own transitive
// dependencies demand -- file_picker against flutter_plugin_android_lifecycle is
// the current example. Pinning every Android library subproject to the app's
// level stops one lagging plugin from failing the whole build. It is safe
// because compileSdk only widens the APIs available at compile time; runtime
// behaviour is governed by targetSdk, which each plugin still sets itself.
//
// It has to be `finalizeDsl`, and the two hooks that read as the obvious
// choices both fail:
//
//   - Configuring the `android` extension directly inside `plugins.withId`
//     runs at *apply* time, which is before the plugin's own `android { }`
//     block. Any plugin that sets its own compileSdk therefore overwrites
//     this one, silently -- measured with file_picker, which pins 34 and
//     failed on AAR metadata against a dependency requiring 36.
//   - `afterEvaluate` runs too late for some plugins ("It is too late to set
//     compileSdk. It has already been read to configure this project.") and
//     still loses to others.
//
// `androidComponents.finalizeDsl` is the one point that is after the
// subproject's build script and before AGP reads the value.
//
// This must be registered BEFORE the evaluationDependsOn below: that call
// forces subproject evaluation, and a hook added afterwards would arrive too
// late to configure anything.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension>(
            "androidComponents",
        ) {
            finalizeDsl { dsl ->
                val current = dsl.compileSdk
                if (current == null || current < 36) dsl.compileSdk = 36
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
