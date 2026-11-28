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
rootProject.name = "HoiTuAuto"
include(":app")
// dùng chung phần lõi (đã có kiểm thử) của 2 app lẻ, không chép code
include(":vq")
project(":vq").projectDir = file("../android-vong-quay/core")
include(":bs")
project(":bs").projectDir = file("../android-ban-suc/core")
include(":cq")
project(":cq").projectDir = file("../android-can-quet/core")
include(":bc")
project(":bc").projectDir = file("../android-ban-co/core")
