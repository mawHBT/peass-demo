#!/bin/bash

DEMO_PROJECT_NAME=demo-project-spring-boot

if [ "$#" -lt 1 ]; then
	branch="master"
else
	branch=$1
fi

if [ ! -z $2 ]; then
    rcaStrategy=$2
else
    rcaStrategy="COMPLETE"
fi

tar -xf "$DEMO_PROJECT_NAME".tar.xz
echo "Cloning branch $branch"
if [ ! -d ../peass ]
then
	startDir=$(pwd)
	cd ..
	git clone -b $branch https://github.com/DaGeRe/peass.git 
	cd peass && ./mvnw clean install -DskipTests -V
	cd $startDir
fi

PEASS_PROJECT=../peass

DEMO_HOME=$(pwd)/$DEMO_PROJECT_NAME
DEMO_PROJECT_PEASS=$(pwd)/"$DEMO_PROJECT_NAME"_peass
EXECUTION_FILE=results/execute_"$DEMO_PROJECT_NAME".json
DEPENDENCY_FILE=results/deps_"$DEMO_PROJECT_NAME".json
CHANGES_DEMO_PROJECT=results/changes_"$DEMO_PROJECT_NAME".json
PROPERTY_FOLDER=results/properties_"$DEMO_PROJECT_NAME"/

VERSION="$(cd "$DEMO_HOME" && git rev-parse HEAD)"

# It is assumed that $DEMO_HOME is set correctly and PeASS has been built!
echo ":::::::::::::::::::::SELECT:::::::::::::::::::::::::::::::::::::::::::"
java -jar $PEASS_PROJECT/distribution/target/peass-distribution-0.1-SNAPSHOT.jar select -folder $DEMO_HOME

INITIALVERSION="510c3f50e68b80ebc80249cc07b249debb2ea9bb"
INITIAL_SELECTED=$(grep "initialversion" -A 1 $DEPENDENCY_FILE | grep "\"version\"" | tr -d " \"," | awk -F':' '{print $2}')
if [ "$INITIAL_SELECTED" != "$INITIALVERSION" ]
then
	echo "Initialversion should be $INITIALVERSION, but was $INITIAL_SELECTED"
	exit 1
fi

INITIAL_TEST=$(grep "initialDependencies" -A 1 $DEPENDENCY_FILE | grep "ExampleTest")

echo $INITIAL_TEST

if [ -z "$INITIAL_TEST" ]
then
    echo "Loading the dependencies did not work: $INITIAL_TEST"
    exit 1
fi


if [ ! -f "$EXECUTION_FILE" ]
then
    echo "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
    echo "$EXECUTION_FILE could not be found!"
    echo "::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"
    exit 1
fi

echo ":::::::::::::::::::::MEASURE::::::::::::::::::::::::::::::::::::::::::"
java -jar $PEASS_PROJECT/distribution/target/peass-distribution-0.1-SNAPSHOT.jar measure -executionfile $EXECUTION_FILE -folder $DEMO_HOME -vms 5 -iterations 5 -warmup 5 -repetitions 5

echo "::::::::::::::::::::GETCHANGES::::::::::::::::::::::::::::::::::::::::"
java -jar $PEASS_PROJECT/distribution/target/peass-distribution-0.1-SNAPSHOT.jar getchanges -data $DEMO_PROJECT_PEASS -dependencyfile $DEPENDENCY_FILE

#Check, if $CHANGES_DEMO_PROJECT contains the correct commit-SHA
TEST_SHA=$(grep -A1 'versionChanges" : {' $CHANGES_DEMO_PROJECT | grep -v '"versionChanges' | grep -Po '"\K.*(?=")')
if [ "$VERSION" != "$TEST_SHA" ]
then
    echo "commit-SHA ("$VERSION") is not equal to the SHA in $CHANGES_DEMO_PROJECT ("$TEST_SHA")!"
    cat results/statistics/"$DEMO_PROJECT_NAME".json
    exit 1
else
    echo "$CHANGES_DEMO_PROJECT contains the correct commit-SHA."
fi

echo "::::::::::::::::::::SEARCHCAUSE:::::::::::::::::::::::::::::::::::::::"
echo "rcaStrategy is: $rcaStrategy"
java -jar $PEASS_PROJECT/distribution/target/peass-distribution-0.1-SNAPSHOT.jar searchcause -vms 3 -iterations 5 -warmup 1 -repetitions 5 -version $VERSION \
    -test de.dagere.peass.ExampleTest\#test \
    -folder $DEMO_HOME \
    -executionfile $EXECUTION_FILE \
    -rcaStrategy $rcaStrategy \
    -propertyFolder $PROPERTY_FOLDER

echo "::::::::::::::::::::VISUALIZERCA::::::::::::::::::::::::::::::::::::::"
java -jar $PEASS_PROJECT/distribution/target/peass-distribution-0.1-SNAPSHOT.jar visualizerca -data $DEMO_PROJECT_PEASS -propertyFolder $PROPERTY_FOLDER

#Check, if a slowdown is detected for Callee#innerMethod
STATE=$(grep -A21 '"call" : "de.dagere.peass.Callee#innerMethod",' results/$VERSION/de.dagere.peass.ExampleTest_test.js \
    | grep '"state" : "SLOWER",' \
    | grep -o 'SLOWER')
if [ "$STATE" != "SLOWER" ]
then
    echo "State for Callee#innerMethod in de.dagere.peass.ExampleTest_test.js has not the expected value SLOWER, but was $STATE!"
    cat results/$VERSION/de.dagere.peass.ExampleTest_test.js
    exit 1
else
    echo "Slowdown is detected for Callee#innerMethod."
fi

SOURCE_METHOD_LINE=$(grep "Callee.method1_" results/$VERSION/de.dagere.peass.ExampleTest_test.js -A 3 \
    | head -n 3 \
    | grep innerMethod)
if [[ "$SOURCE_METHOD_LINE" != *"innerMethod();" ]]
then
    echo "Line could not be detected - source reading probably failed."
    echo "SOURCE_METHOD_LINE: $SOURCE_METHOD_LINE"
    exit 1
else
    echo "SOURCE_METHOD_LINE is correct."
fi