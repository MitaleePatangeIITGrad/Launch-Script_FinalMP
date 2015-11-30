# Launch-Script_FinalMP
Launch the shell script for aws cli commands

This repository launches the aws services with parameters with the help of Launch-steps script

The following services are launched sequentially -

    1. EC2 Instances
    2. Load Balancer
    3. Launch Configuration
    4. Auto Scaling Group
    5. CloudWatch Metrics with SNS and Scaling alarm actions
    6. RDS Database
    7. SNS Topic
    8. Create tables (User,Gallery,SNS, Introspection) in the DB instance

This script takes 7 parameters in the following sequence -

    1. $1 - ami image-id
    2. $2 - count
    3. $3 - instance-type
    4. $4 - security-group-ids
    5. $5 - subnet-id
    6. $6 - key-name
    7. $7 - iam-profile
