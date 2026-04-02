if (NOT DEFINED INPUT_XML OR NOT DEFINED OUTPUT_XML)
    message(FATAL_ERROR "INPUT_XML and OUTPUT_XML must be set")
endif()

file(READ "${INPUT_XML}" PROTOCOL_XML)
string(REPLACE "name=\"namespace\"" "name=\"name_space\"" PROTOCOL_XML "${PROTOCOL_XML}")
file(WRITE "${OUTPUT_XML}" "${PROTOCOL_XML}")
