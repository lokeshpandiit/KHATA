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
    project.evaluationDependsOn(":app")
}

// Configure Android library compileSdk when its plugin is applied.
// Avoid afterEvaluate(), which can fail when the project is already evaluated.
subprojects {
    plugins.withId("com.android.library") {
        val androidExtension = extensions.findByName("android")
            ?: error("Android extension not found for $path")
        val compileSdkSetter = androidExtension.javaClass.methods.firstOrNull {
            (it.name == "setCompileSdk" || it.name == "setCompileSdkVersion") &&
                it.parameterTypes.singleOrNull() == Int::class.javaPrimitiveType
        } ?: error("Could not configure compileSdk for $path")
        compileSdkSetter.invoke(androidExtension, 36)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
