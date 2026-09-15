cmake_minimum_required(VERSION 3.25)

project(LoopGeneratorVST3
    VERSION 0.3.0
    DESCRIPTION "Stable Audio loop generator VST3"
    LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "Build architecture")
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.0 CACHE STRING "Minimum macOS version")

include(CTest)

set(LOOP_GENERATOR_JUCE_DIR "" CACHE PATH "Path to a JUCE 8.0.12 source checkout")
if(NOT LOOP_GENERATOR_JUCE_DIR AND DEFINED ENV{LOOP_GENERATOR_JUCE_DIR})
    set(LOOP_GENERATOR_JUCE_DIR "$ENV{LOOP_GENERATOR_JUCE_DIR}")
endif()
if(NOT EXISTS "${LOOP_GENERATOR_JUCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR
        "JUCE 8.0.12 is required. Pass -DLOOP_GENERATOR_JUCE_DIR=/path/to/JUCE "
        "or run scripts/setup_vst3.sh.")
endif()

add_subdirectory("${LOOP_GENERATOR_JUCE_DIR}" "${CMAKE_BINARY_DIR}/JUCE")

add_library(LoopGeneratorPluginCore STATIC
    Sources/LoopGeneratorVST3/GenerationService.cpp
    Sources/LoopGeneratorVST3/GenerationService.h
    Sources/LoopGeneratorVST3/GeneratedLoop.cpp
    Sources/LoopGeneratorVST3/GeneratedLoop.h)
target_include_directories(LoopGeneratorPluginCore PUBLIC Sources/LoopGeneratorVST3)
target_compile_definitions(LoopGeneratorPluginCore PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    LOOP_GENERATOR_VERSION="${PROJECT_VERSION}")
target_link_libraries(LoopGeneratorPluginCore PUBLIC
    juce::juce_audio_formats
    juce::juce_core)

juce_add_plugin(LoopGeneratorVST3
    COMPANY_NAME "Loop Generator"
    BUNDLE_ID "com.loopgenerator.vst3"
    PLUGIN_MANUFACTURER_CODE LGen
    PLUGIN_CODE LpG3
    FORMATS VST3
    PRODUCT_NAME "Loop Generator"
    DESCRIPTION "Stable Audio loop generator"
    IS_SYNTH FALSE
    NEEDS_MIDI_INPUT FALSE
    NEEDS_MIDI_OUTPUT FALSE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD FALSE
    VST3_CATEGORIES Fx)

juce_generate_juce_header(LoopGeneratorVST3)
target_sources(LoopGeneratorVST3 PRIVATE
    Sources/LoopGeneratorVST3/PluginEditor.cpp
    Sources/LoopGeneratorVST3/PluginEditor.h
    Sources/LoopGeneratorVST3/PluginProcessor.cpp
    Sources/LoopGeneratorVST3/PluginProcessor.h)
target_compile_definitions(LoopGeneratorVST3 PRIVATE
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0)
target_link_libraries(LoopGeneratorVST3 PRIVATE
    LoopGeneratorPluginCore
    juce::juce_audio_utils
    juce::juce_gui_extra
    juce::juce_recommended_config_flags
    juce::juce_recommended_warning_flags)

add_custom_command(TARGET LoopGeneratorVST3_VST3 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory
        "$<TARGET_BUNDLE_DIR:LoopGeneratorVST3_VST3>/Contents/Resources/runtime/stable_audio"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/runtime/stable_audio/infer.py"
        "$<TARGET_BUNDLE_DIR:LoopGeneratorVST3_VST3>/Contents/Resources/runtime/stable_audio/infer.py"
    COMMAND chmod +x
        "$<TARGET_BUNDLE_DIR:LoopGeneratorVST3_VST3>/Contents/Resources/runtime/stable_audio/infer.py"
    COMMAND codesign --force --deep --sign - --timestamp=none
        "$<TARGET_BUNDLE_DIR:LoopGeneratorVST3_VST3>"
    VERBATIM)

if(BUILD_TESTING)
    juce_add_console_app(LoopGeneratorVST3Tests PRODUCT_NAME "Loop Generator VST3 Tests")
    target_sources(LoopGeneratorVST3Tests PRIVATE
        Tests/LoopGeneratorVST3Tests/LoopGeneratorVST3Tests.cpp
        Sources/LoopGeneratorVST3/PluginEditor.cpp
        Sources/LoopGeneratorVST3/PluginProcessor.cpp)
    target_include_directories(LoopGeneratorVST3Tests PRIVATE Sources/LoopGeneratorVST3)
    target_compile_definitions(LoopGeneratorVST3Tests PRIVATE
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0)
    target_link_libraries(LoopGeneratorVST3Tests PRIVATE
        LoopGeneratorPluginCore
        juce::juce_audio_utils
        juce::juce_gui_extra)
    add_test(NAME loop_generator_vst3_core COMMAND LoopGeneratorVST3Tests)

    juce_add_console_app(LoopGeneratorVST3HostSmoke PRODUCT_NAME "Loop Generator VST3 Host Smoke")
    target_sources(LoopGeneratorVST3HostSmoke PRIVATE
        Tests/LoopGeneratorVST3Tests/PluginHostSmoke.cpp
        Sources/LoopGeneratorVST3/PluginEditor.cpp
        Sources/LoopGeneratorVST3/PluginProcessor.cpp)
    target_include_directories(LoopGeneratorVST3HostSmoke PRIVATE Sources/LoopGeneratorVST3)
    target_compile_definitions(LoopGeneratorVST3HostSmoke PRIVATE
        JUCE_PLUGINHOST_VST3=1
        JUCE_WEB_BROWSER=0
        JUCE_USE_CURL=0
        LOOP_GENERATOR_NO_PLUGIN_ENTRY=1
        LOOP_GENERATOR_TEST_VST3="$<TARGET_BUNDLE_DIR:LoopGeneratorVST3_VST3>")
    target_link_libraries(LoopGeneratorVST3HostSmoke PRIVATE
        LoopGeneratorPluginCore
        juce::juce_audio_processors
        juce::juce_audio_utils
        juce::juce_gui_extra)
    add_dependencies(LoopGeneratorVST3HostSmoke LoopGeneratorVST3_VST3)
    add_test(NAME loop_generator_vst3_host COMMAND LoopGeneratorVST3HostSmoke)
endif()
