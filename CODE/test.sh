#!/bin/bash
rm test.log

#exec 2>test.log

for i in $(ls error*.100 | sed -e 's/\.[100]*$//')
do
    echo $i
    grep -E "(/*)+(*/)" $i.100
    ./C100 $i
    echo --------------------------------------------------------------------------
done
