#!/bin/bash

TRACE=1
TMP_PREFIX="__tmp__"
NUMBER_OF_RANDOM_DIGITS=10
EXIT_CODE_SUCCESS=0
EXIT_CODE_ERROR=1
TMP_RANDOM_NUMBER=

GenerateRandomNumber ()
{
    local LCL_NUMBER_OF_DIGITS=$1
    local LCL_RETURN=$2
    local LCL_EXIT_CODE=0
    local LCL_RETURN_VALUE=

    [ $TRACE != 0 ] && echo "-> ${FUNCNAME[0]} ($*)"
    # [ $TRACE != 0 ] && echo "   \$LCL_NUMBER_OF_DIGITS = $LCL_NUMBER_OF_DIGITS"

    for (( c=0; c<=$LCL_NUMBER_OF_DIGITS; c++ ))
    do
        LCL_RETURN_VALUE=$LCL_RETURN_VALUE$(( $RANDOM % 10))
    done

    [ $TRACE != 0 ] && echo "<- ${FUNCNAME[0]} (RANDOM_NUMBER: $LCL_RETURN_VALUE)"
    eval $LCL_RETURN=\$LCL_RETURN_VALUE
    return $LCL_EXIT_CODE
}

LowerFileName ()
{
    local LCL_FILE_NAME=$1
    local LCL_TEMP_SUFFIX=$2
    local LCL_EXIT_CODE=0

    [ $TRACE != 0 ] && echo "-> ${FUNCNAME[0]} ($*)"
    # [ $TRACE != 0 ] && echo "   \$LCL_FILE_NAME = $LCL_FILE_NAME"
    # [ $TRACE != 0 ] && echo "   \$LCL_TEMP_SUFFIX = $LCL_TEMP_SUFFIX"

    local LCL_FILE_NAME_LOWER=$( echo $LCL_FILE_NAME | tr 'A-Z' 'a-z' )
    [ $TRACE != 0 ] && echo "   old file name: $LCL_FILE_NAME"
    [ $TRACE != 0 ] && echo "   tmp file name: $LCL_FILE_NAME$LCL_TEMP_SUFFIX"
    [ $TRACE != 0 ] && echo "   new file name: $LCL_FILE_NAME_LOWER"

    mv -n $LCL_FILE_NAME $LCL_FILE_NAME$LCL_TEMP_SUFFIX || exit 1
    mv -n $LCL_FILE_NAME$LCL_TEMP_SUFFIX $LCL_FILE_NAME_LOWER || exit 1

    [ $TRACE != 0 ] && echo "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
}

# =========== main ================
[ $TRACE != 0 ] && echo "-> $0"

for fileName in $( ls | grep [A-Z] )
do
    GenerateRandomNumber $NUMBER_OF_RANDOM_DIGITS TMP_RANDOM_NUMBER || exit $EXIT_CODE_ERROR
    LowerFileName $fileName $TMP_PREFIX$TMP_RANDOM_NUMBER
done

[ $TRACE != 0 ] && echo "<- $0"
exit $EXIT_CODE_SUCCESS
