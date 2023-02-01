#!/bin/sh

a=0
while [ $a -lt 500 ]
do
   echo $a
   echo "Starting  deployment ..."
   a=`expr $a + 1`
   sleep 5
done
