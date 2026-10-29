import os
import boto3
import logging
import urllib.parse
from email.message import EmailMessage

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
ses = boto3.client('sesv2')

def handler(event, context):
    record = event['Records'][0]
    bucket = record['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(record['s3']['object']['key'])

    logger.info(f"report-mailer triggered trigger=s3 bucket={bucket} key={key}")

    response = s3.get_object(Bucket=bucket, Key=key)
    csv_data = response['Body'].read()

    filename = os.path.basename(key)
    sender = os.environ['SENDER_EMAIL']
    recipient = os.environ['RECIPIENT_EMAIL']

    msg = EmailMessage()
    msg['Subject'] = f"Weekly meetings report {filename.replace('.csv', '')}"
    msg['From'] = sender
    msg['To'] = recipient
    msg.set_content("Please find attached the weekly meetings report.")
    msg.add_attachment(csv_data, maintype="text", subtype="csv", filename=filename)

    ses.send_email(
        Content={'Raw': {'Data': msg.as_bytes()}}
    )
    return {'status': 'sent', 'key': key}
