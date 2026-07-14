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

    // file_picker 11 skips KGP on AGP 9 assuming built-in Kotlin, while this
    // Flutter project temporarily opts out of built-in Kotlin for other plugins.
    if (project.name == "file_picker") {
        project.pluginManager.apply("org.jetbrains.kotlin.android")
        project.tasks
            .withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>()
            .configureEach {
                compilerOptions.jvmTarget.set(
                    org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                )
            }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
