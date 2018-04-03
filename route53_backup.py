#!/usr/bin/env python

import os
import boto3
import time
import csv
import json
from datetime import datetime
from botocore.exceptions import ClientError

route53 = boto3.client('route53')
s3 = boto3.client('s3', region_name = 'us-east-1')

def get_route53_hosted_zones(next_zone=None):
    if(next_zone):
        response = route53.list_hosted_zones_by_name(
            DNSName=next_zone[0],
            HostedZoneId=next_zone[1]
        )
    else:
        response = route53.list_hosted_zones_by_name()
        hosted_zones = response['HostedZones']
        if(response['IsTruncated']):
            hosted_zones += get_route53_hosted_zones(
                (response['NetDNSName'],
                response['NextHostedZoneId'])
            )
    return hosted_zones


def get_route53_zone_records(zone_id, next_record=None):
    if(next_record):
        response = route53.list_resource_record_sets(
            HostedZoneId=zone_id,
            StartRecordName=next_record[0],
            StartRecordType=next_record[1]
        )
    else:
        response = route53.list_resource_record_sets(HostedZoneId=zone_id)
    zone_records = response['ResourceRecordSets']
    if (response['IsTruncated']):
        zone_records += get_route53_zone_records(
            zone_id,
            (response['NextRecordName'],
            response['NextRecordType'])
        )
    return zone_records


def get_record_value(record):
    try:
        value = [':'.join(
            ['ALIAS', record['AliasTarget']['HostedZoneId'],
            record['AliasTarget']['DNSName']]
        )]
    except KeyError:
        value = []
        for v in record['ResourceRecords']:
            value.append(v['Value'])
    return value

def try_record(test,record):
    try:
        value = record[test]
    except KeyError:
        value = ''
    except TypeError:
        value = ''
    return value

def write_zone_to_json(zone, zone_records):
    zone_file_name = '/tmp/' + zone['Name'] + 'json'
    with open(zone_file_name, 'w') as json_file:
        json.dump(zone_records, json_file, indent=4)
    return zone_file_name


def write_zone_to_csv(zone,zone_records):
    zone_file_name = '/tmp/' + zone['Name'] + 'csv'
    with open(zone_file_name, 'w') as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow([
            'NAME', 'TYPE', 'VALUE',
            'TTL', 'REGION', 'WEIGHT',
            'SETID','FAILOVER', 'EVALUATE_HEALTH'
        ])
        for record in zone_records:
            csv_row = [''] * 9
            csv_row[0] = record['Name']
            csv_row[1] = record['Type']
            csv_row[3] = try_record('TTL', record)
            csv_row[4] = try_record('Region', record)
            csv_row[5] = try_record('Weight', record)
            csv_row[6] = try_record('SetIdentifier', record)
            csv_row[7] = try_record('Failover', record)
            csv_row[8] = try_record('EvaluateTargetHealth',
                try_record('AliasTarget', record)
            )
            value = get_record_value(record)
            for v in value:
                csv_row[2] = v
                writer.writerow(csv_row)
    return zone_file_name

def upload_to_s3(folder, filename, bucket_name, key):
    key = folder + '/' + key
    s3.upload_file(filename, bucket_name, key)

def handler(event, context):
    s3_bucket_name = event['bucket_name']
    time_stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ",
    datetime.utcnow().utctimetuple()
    )
    hosted_zones = get_route53_hosted_zones()
    for zone in hosted_zones:
        zone_folder = ( time_stamp + '/' + zone['Name'][:-1])
        zone_records = get_route53_zone_records(zone['Id'])
        upload_to_s3(
            zone_folder,
            write_zone_to_csv(zone, zone_records),
            s3_bucket_name,
            (zone['Name'] + 'csv')
        )

        upload_to_s3(
            zone_folder,
            write_zone_to_json(zone, zone_records),
            s3_bucket_name,
            (zone['Name'] + 'json')
        )
    return True


if __name__ == "__main__":
    handler(event={}, context=None)
