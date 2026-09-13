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
// This must be registered BEFORE the evaluationDependsOn below: that call
// forces subproject evaluation, and a hook added afterwards would arrive too
// late to configure anything.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            val current = compileSdk
            if (current == null || current < 36) compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
