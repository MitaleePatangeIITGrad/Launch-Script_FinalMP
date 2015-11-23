#!/bin/bash

# This program takes 7 arguments in the following order
# $1 - ami image-id
# $2 - count
# $3 - instance-type
# $4 - security-group-ids
# $5 - subnet-id
# $6 - key-name
# $7 - iam-profile

declare -a ELBNAME=itmo544-mrp-lb
LAUNCHCONFNAME=itmo544-mrp-launch-config
AUTOSCALINGNAME=itmo544-mrp-asg
DBSUBNETNAME=itmo544-mrp-subnet
DBINSTANCEIDENTIFIER=itmo544-mrp-mysql-db
DBINSTANCEREADONLY=itmo544-mrp-mysql-db-readonly
DBUSERNAME=controller
DBPASSWORD=ilovebunnies
DBNAME=customerrecords
SUBNET1=subnet-14fcce3f
SUBNET2=subnet-1e5e7547
TOPICNAME=mp2-notify-mrp
METRICNAME=mp2-cloud-alert-mrp
PHONENUMBER=19143193344

#Step 0: Cleanup all the existing stuff

echo -e "\n Cleanup script will cleanup all existing data"

../Environment_MP2/cleanup.sh

#Step 1a: Launch the instances and provide the user-data via the install-env.sh

echo -e "\n Launching Instances"

declare -a INSTANCELIST 
INSTANCELIST=(`aws ec2 run-instances --image-id $1 --count $2 --instance-type $3 --security-group-ids $4 --subnet-id $5 --key-name $6 --associate-public-ip-address --iam-instance-profile Name=$7 --user-data file://../Environment_MP2/install-env.sh --output text | grep INSTANCES | awk {' print $7'}`)

for i in {0..60}; do echo -ne '.'; sleep 1;done

#Step 1b: Listing the instances

echo -e "\n Listing Instances, filtering their instance-id, adding them to an ARRAY and sleeping 15 seconds"
for i in {0..15}; do echo -ne '.'; sleep 1;done

echo -e "\n The instance ids are \n" ${INSTANCELIST[@]}

echo -e "\n Finished launching EC2 Instances, waiting for the instances to be in running state and sleeping 60 seconds"
for i in {0..60}; do echo -ne '.'; sleep 1;done

aws ec2 wait instance-running --instance-ids ${INSTANCELIST[@]} 


#Step 2a:  Create a ELBURL variable, and create a load balancer. 
 
declare -a ELBURL

ELBURL=(`aws elb create-load-balancer --load-balancer-name $ELBNAME --listeners Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80 --subnets $5 --security-groups $4`) 

echo -e "\n Load Balancer link is \n" ${ELBURL[@]}


#Step 2b: Configure the elb configure-health-check and attach cookie stickiness policy

echo -e "\n Configuring health and cookie stickiness policies for load balancer"

aws elb configure-health-check --load-balancer-name $ELBNAME --health-check Target=HTTP:80/index.php,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3

aws elb create-lb-cookie-stickiness-policy --load-balancer-name $ELBNAME --policy-name itmo544-mrp-lb-cookie-policy --cookie-expiration-period 60

aws elb set-load-balancer-policies-of-listener --load-balancer-name $ELBNAME --load-balancer-port 80 --policy-names itmo544-mrp-lb-cookie-policy

echo -e "\n Finished ELB health check and sleeping 25 seconds"
for i in {0..25}; do echo -ne '.'; sleep 1;done


#Step 2c: Register the instances with the load balancer

aws elb register-instances-with-load-balancer --load-balancer-name $ELBNAME --instances ${INSTANCELIST[@]}

echo -e "\n Finished launching ELB and registering instances, now sleeping for 25 seconds " 
for i in {0..25}; do echo -ne '.'; sleep 1;done


#Step 3a: Configure launch configuration

echo -e "\n Creating Launch Configuration"
aws autoscaling create-launch-configuration --launch-configuration-name $LAUNCHCONFNAME --iam-instance-profile $7 --user-data file://../Environment_MP2/install-env.sh --key-name $6 --instance-type $3 --security-groups $4 --image-id $1

echo -e "\n Finished launching configuration and sleeping 25 seconds"
for i in {0..25}; do echo -ne '.'; sleep 1;done

#Step 3b: Configure auto scaling groups

echo -e "\n Creating Auto scaling group"
aws autoscaling create-auto-scaling-group --auto-scaling-group-name $AUTOSCALINGNAME --launch-configuration-name $LAUNCHCONFNAME --load-balancer-names $ELBNAME --health-check-type ELB --min-size 3 --max-size 6 --desired-capacity 3 --default-cooldown 600 --health-check-grace-period 120 --vpc-zone-identifier $5

echo -e "\n Finished creating auto scaling group and sleeping 25 seconds"
for i in {0..25}; do echo -ne '.'; sleep 1;done

#Step 4a: Create scale out and scale in policies

declare -a SPURL

SPURL=(`aws autoscaling put-scaling-policy --policy-name itmo544-mrp-scaleout-policy --auto-scaling-group-name $AUTOSCALINGNAME --scaling-adjustment 3 --adjustment-type ChangeInCapacity`)

echo -e "\n The Scale out policy ARN " ${SPURL[@]}

declare -a SPURL1

SPURL1=(`aws autoscaling put-scaling-policy --policy-name itmo544-mrp-scalein-policy --auto-scaling-group-name $AUTOSCALINGNAME --scaling-adjustment -3 --adjustment-type ChangeInCapacity`)

echo -e "\n The Scale in policy ARN " ${SPURL1[@]}

#Step 4b: Create an SNS topic for cloud watch metrics subscriptions

METRICARN=(`aws sns create-topic --name $METRICNAME`)
aws sns set-topic-attributes --topic-arn $METRICARN --attribute-name DisplayName --attribute-value $METRICNAME

#Step 4c: Subscribe user phone number to the topic

aws sns subscribe --topic-arn $METRICARN --protocol sms --notification-endpoint $PHONENUMBER

#Step 4d: Launch cloud metrics for the auto scaling group and sns topic

aws cloudwatch put-metric-alarm --alarm-name AddCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 60 --threshold 30 --comparison-operator GreaterThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=$AUTOSCALINGNAME" --evaluation-periods 1 --unit Percent --alarm-actions ${SPURL[@]} ${METRICARN[@]}

aws cloudwatch put-metric-alarm --alarm-name RemoveCapacity --metric-name CPUUtilization --namespace AWS/EC2 --statistic Average --period 60 --threshold 10 --comparison-operator LessThanOrEqualToThreshold --dimensions "Name=AutoScalingGroupName,Value=$AUTOSCALINGNAME" --evaluation-periods 1 --unit Percent --alarm-actions ${SPURL1[@]} ${METRICARN[@]}

echo -e "\n Finished creating cloud watch metrics and sleeping 25 seconds"
for i in {0..25}; do echo -ne '.'; sleep 1;done


#Step 5a: Create a subnet group

echo -e "\n Creating subnet group for db instance"

aws rds create-db-subnet-group --db-subnet-group-name $DBSUBNETNAME --db-subnet-group-description MiniProject1 --subnet-ids  $SUBNET1 $SUBNET2

#Step 5b: Launch RDS mysql database

echo -e "\n Creating db instance"
aws rds create-db-instance --db-instance-identifier $DBINSTANCEIDENTIFIER --allocated-storage 20 --db-instance-class db.t1.micro --engine mysql --master-username $DBUSERNAME --master-user-password $DBPASSWORD --engine-version 5.6.23 --license-model general-public-license --no-multi-az --storage-type standard --publicly-accessible --availability-zone us-east-1a --db-name $DBNAME --port 3306  --auto-minor-version-upgrade --preferred-maintenance-window mon:00:00-mon:01:30 --vpc-security-group-ids $4 --db-subnet-group-name $DBSUBNETNAME

#Step 5c: Wait for the instance to be available

echo -e "\n Waiting after launching RDS mysql database to make it available for 10 minutes"
for i in {0..600}; do echo -ne '.'; sleep 1;done

aws rds wait db-instance-available --db-instance-identifier $DBINSTANCEIDENTIFIER

#Step 5d: Launch RDS mysql database read replica

echo -e "\n Creating a read replica for the db instance"

aws rds create-db-instance-read-replica --db-instance-identifier $DBINSTANCEREADONLY --source-db-instance-identifier $DBINSTANCEIDENTIFIER --publicly-accessible --availability-zone us-east-1a

#Step 5e: Wait for the instance to be available

echo -e "\n Finished launching RDS readonly replica for mysql database and sleeping 10 minutes"
for i in {0..600}; do echo -ne '.'; sleep 1;done


#Step 6a: Create an SNS topic for image upload subscriptions
TOPICARN=(`aws sns create-topic --name $TOPICNAME`)
aws sns set-topic-attributes --topic-arn $TOPICARN --attribute-name DisplayName --attribute-value $TOPICNAME   


#Step 6b: Describe db instances

declare -a DBINSTANCEARR

DBINSTANCEARR=(`aws rds describe-db-instances --output text | grep ENDPOINT | awk {' print $2'}`)

echo  ${DBINSTANCEARR[@]}


#Step 6c: Connect to MySQL Database

echo -e "\n Connecting to MySQL database to create table"

mysql -h ${DBINSTANCEARR[0]} -P 3306 -u $DBUSERNAME -p$DBPASSWORD  << EOF

use $DBNAME ;
CREATE TABLE IF NOT EXISTS user (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, uname VARCHAR(20), email VARCHAR(32), phone VARCHAR(20), issubscribed VARCHAR(2),UNIQUE KEY(phone));
CREATE TABLE IF NOT EXISTS gallery (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,userid INT,s3rawurl VARCHAR(256), s3finishedurl VARCHAR(256), filename VARCHAR(256), status INT, timestamp datetime DEFAULT CURRENT_TIMESTAMP, FOREIGN KEY (userid) REFERENCES user(id)) ;
CREATE TABLE IF NOT EXISTS sns(id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, displayname VARCHAR(50) NOT NULL, arn VARCHAR(255) NOT NULL);
show tables;
INSERT INTO sns (displayname,arn) VALUES ('$TOPICNAME','$TOPICARN');
INSERT INTO sns (displayname,arn) VALUES ('$METRICNAME','$METRICARN');

EOF

#Step 7: Launch ELB in firefox

echo -e "\n Waiting an additional 1 minute before opening the ELB in browser"
for i in {0..60}; do echo -ne '.'; sleep 1;done

firefox $ELBURL &

echo -e "All Done"


