# README

## Deploying the Rails API server (Aragorn)
- Build new container using `bin/dbuild.sh`
- Push container to Docker using `bin/dpush.sh`
- SSH to AWS Lightsail instance
- Navigate to `/srv/docker`
- Pull container from Docker using `docker pull brendandixon/my-recalls:latest`)
- Stop the active instance using `docker-compose down`
- Remove old docker container (e.g., `docker rmi f678`)
- Restart the container (using the latest image) using `docker-compose up -d`
- As needed, SSH into the container using `docker exec -it docker_app_1 bash`

## Deploying the ReactJS App (Arwen)
- Build using `bin/cbuild.sh prod`'
- Create a new S3 folder (using a `YYYY-MM-DDTHH-mm-ss` format in UTC time) in the `myrecalls-today` bucket
- Copy the contents of `arwen/dist` to the folder
- Navigate to CloudFront and the S3 bucket distribution (i.e., `myrecalls-today.s3.amazonaws.com`)
- Set the Origin Path (under Origin Settings) to the new S3 folder name (with a leading slash)
- Wait for distibution to complete

## Deploying the Lambda Scripts (Arwen)
- Build using `bin/sbuild.sh xxxxx prod` where `xxxxx` is `feeder` or `Alerter`
- Navigate to Lambda, select the appropriate function, and upload the .ZIP file (e.g., `feeder.production.zip`)
- Save and test the package
- Publish a new version, using the most recent Git commit as the version identifier
- Navigate to CloudWatch, select Rules
- Edit each Rule to use the most recent version of the corresponding Lambda function
