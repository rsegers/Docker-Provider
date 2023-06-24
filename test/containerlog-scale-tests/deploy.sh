#!/bin/bash

## each job generates 1 kps rate,

## define N value, 10K eps (each log line size 1KB), N value be 10 and similarly if its 50K eps, N value must be 50
N=10

for ((i=1; i <= N; i++))
do
  kubectl create ns test"$i"
  kubectl apply -f log-generator-job-app.yaml -n test"$i"
done




