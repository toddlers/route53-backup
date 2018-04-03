#!/bin/bash
set -e

rm -rf ./output/*
pip3 install -r requirements.txt -t ./output
cp route53_backup.py ./output/
if [ -f "./route53_backup_lambda.zip" ];then
  rm ./route53_backup_lambda.zip
fi
cd ./output && zip -r ../route53_backup_lambda.zip *

# Run terraform apply
cd .. && terraform apply
