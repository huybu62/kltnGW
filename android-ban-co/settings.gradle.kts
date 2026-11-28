pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "BanCo"
include(":core")
// dùng chung tiện ích ảnh / chữ của lõi Ban Sức
include(":bs")
project(":bs").projectDir = file("../android-ban-suc/core")
