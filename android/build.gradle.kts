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
subprojects {
    // The OpenCV plugin module (:opencv_core) compiles against android-33, but
    // its androidx.exifinterface transitive dependency demands compileSdk 34+.
    // Force every Android subproject to a modern compileSdk. Reflection avoids
    // a compile-time dependency on a specific AGP extension type. Registered
    // before evaluationDependsOn below, so the project isn't already evaluated.
    afterEvaluate {
        val android = project.extensions.findByName("android") ?: return@afterEvaluate
        runCatching {
            android.javaClass
                .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                .invoke(android, 36)
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
