#!/bin/bash

# Launch a build on the current machine or on one of its virtual
# submachines.

# This script must not exit without updating the status in $statusFile
# otherwise the caller will wait forever.

if [ "$#" -lt 3 ]; then echo Usage: $0 machine buildDir statusFile; exit; fi

# Note: buildDir must be relative to $HOME
machine=$1; buildDir=$2; statusFile=$3;
doneFile="buildDone.txt" # Put here the build name when it is done

cd $HOME
if [ ! -d "$buildDir" ]; then echo "Error: Directory: $buildDir does not exist"; exit 1; fi;
cd $buildDir

user=$(whoami)
if [ "$(echo $machine | grep centos)" != "" ]; then
    # The case of virtual machines
    user=build
    # If the machine is not running, start it
    isRunning=$(virsh list --all 2>/dev/null |grep running | grep $machine)
    if [ "$isRunning" == "" ]; then
        virsh start $machine
    fi
    # Wait until the machine is fully running
    while [ 1 ]; do
        ans=$(ssh "$user@$machine" ls $buildDir 2>/dev/null)
        if [ "$ans" != "" ]; then break; fi
        echo $(date) "Sleping while waiting for $machine to start"
        sleep 60
    done
fi

# Make sure all scripts are up-to-date on the machine above to run things on
./auto_build/refresh_code.sh $user $machine $buildDir 2>/dev/null

# Ensure we first wipe $doneFile, then launch the build
outputBuildFile="$buildDir/output_build_"$machine".txt"
ssh $user@$machine "rm -f $buildDir/$doneFile"
ssh $user@$machine "nohup nice -19 $buildDir/auto_build/build.sh $buildDir $doneFile > $outputBuildFile 2>&1&"

# Wait until the build finished
while [ 1 ]; do
  asp_tarball=$(ssh "$user@$machine" "cat $buildDir/$doneFile 2>/dev/null" 2>/dev/null)
  if [ "$asp_tarball" != "" ]; then break; fi
  echo $(date) "Sleping while waiting for the build on $machine to finish"
  sleep 60
done

# Copy back the obtained tarball and mark it as built
if [ "$asp_tarball" != "Fail" ]; then
    mkdir -p asp_tarballs
    echo Copying $user@$machine:$buildDir/$asp_tarball to asp_tarballs
    rsync -avz $user@$machine:$buildDir/$asp_tarball asp_tarballs
fi
echo $asp_tarball build_done > $statusFile

ssh $user@$machine "cat $outputBuildFile" 2>/dev/null # append to curr logfile
