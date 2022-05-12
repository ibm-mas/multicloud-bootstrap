#!/usr/bin/python

import email, smtplib, ssl

from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

subject_details = "MAS Provisioning Notification (contains an attachment)"
body_details = "[MESSAGE-TEXT]\n\nMAS provisioning status: [STATUS]#[STATUS-MESSAGE]\nRegion: [REGION]\nUnique String: [UNIQ-STR]\nOpenShift Cluster URL: [OPENSHIFT-CLUSTER-CONSOLE-URL]\nOpenShift API URL: [OPENSHIFT-CLUSTER-API-URL]\nOpenShift User: [OCP-USER]\nSLS Endpoint URL:\nBAS Endpoint URL: \nMAS Initial Setup URL: [MAS-URL-INIT-SETUP]\nMAS Admin URL: [MAS-URL-ADMIN]\nMAS Workspace URL: [MAS-URL-WORKSPACE]\n"
subject_creds = "MAS Provisioning Notification (contains credentials)"
body_creds = "MAS provisioning status: [STATUS]\nRegion: [REGION]\nUnique String: [UNIQ-STR]\nOpenShift Password: [OCP-PASSWORD]\nMAS Password: [MAS-PASSWORD]"
sender_email = "noreply@maximo.ibm.com"
recipients = [[RECEPIENT]]

# Create a multipart message and set headers
message_details = MIMEMultipart()
message_details["From"] = sender_email
message_details["To"] = ", ".join(recipients)
message_details["Subject"] = subject_details

message_creds = MIMEMultipart()
message_creds["From"] = sender_email
message_creds["To"] = ", ".join(recipients)
message_creds["Subject"] = subject_creds

# Add body to email
message_details.attach(MIMEText(body_details, "plain"))
message_creds.attach(MIMEText(body_creds, "plain"))

filename = "[CERT-FILE]"  # In same directory as script

# Open file in binary mode
with open(filename, "rb") as attachment:
    part = MIMEBase("application", "octet-stream")
    part.set_payload(attachment.read())

# Encode file in ASCII characters to send by email    
encoders.encode_base64(part)

# Add header as key/value pair to attachment part
part.add_header(
    "Content-Disposition",
    f"attachment; filename= {filename}",
)

# Add attachment to message and convert message to string
message_details.attach(part)
text_details = message_details.as_string()
text_creds = message_creds.as_string()

try:
   smtpObj = smtplib.SMTP("[SMTP-HOST]", [SMTP-PORT])
   smtpObj.login("[SMTP-USERNAME]", "[SMTP-PASSWORD]")
   smtpObj.sendmail(sender_email, recipients, text_details)
   smtpObj.sendmail(sender_email, recipients, text_creds)
   print("Successfully sent email")
except SMTPException:
   print("Error: unable to send email")

smtpObj.quit()
