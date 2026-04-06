if (NOT DEFINED INPUT_XML OR NOT DEFINED OUTPUT_XML)
    message(FATAL_ERROR "INPUT_XML and OUTPUT_XML must be set")
endif()

file(READ "${INPUT_XML}" PROTOCOL_XML)
string(REPLACE "name=\"namespace\"" "name=\"name_space\"" PROTOCOL_XML "${PROTOCOL_XML}")

# Only write when content has changed to avoid bumping mtime on every CMake run,
# which would otherwise cause spurious rebuilds of the protocol C/H files and a
# full relink of the binary.
if(EXISTS "${OUTPUT_XML}")
    file(READ "${OUTPUT_XML}" EXISTING_XML)
    if(EXISTING_XML STREQUAL PROTOCOL_XML)
        return()
    endif()
endif()

file(WRITE "${OUTPUT_XML}" "${PROTOCOL_XML}")
