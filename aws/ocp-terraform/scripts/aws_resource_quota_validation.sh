#!/bin/bash

DEPLOY_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
VENV="$HOME/.aws_python_venv"

# create the virtual environment if needed.
if [[ ! -d "$VENV" ]]; then
    echo "Create virtual python environment"
    python3 -m venv $VENV
fi

# Activate the python virtual environment.
if [[ ! -n "$VIRTUAL_ENV" ]]; then
    echo "Activate virtual python environment"
    source $VENV/bin/activate
fi

# Check if required python modules are already installed in virtual env
while IFS= read -r line; do
    pip freeze | grep $line
done < $DEPLOY_HOME/libs_aws/requirements.txt >/dev/null

exit_code=$?

# Skip python module install if already in virtual env
if [[ ${exit_code} -eq 0 ]] ; then
    echo "Required python modules already in virtual python environment"
else
    # Install python modules
    echo "Install required python modules in the virtual python environment"
    python3 -m pip install --upgrade pip > /dev/null
    python3 -m pip install -r $DEPLOY_HOME/libs_aws/requirements.txt > /dev/null
fi

# Get number of s3 buckets used
s3bucket_used=$(aws s3api list-buckets --query "Buckets | length(@)" --output text)

# Echo the number of s3 buckets used
echo "Number of S3 buckets used: $s3bucket_used"

if [ "$s3bucket_used" -gt 10000 ]; then
    echo "Number of s3 buckets exceeds 10000. Exiting..."
    exit 1
fi

# Run the python program itself
python $DEPLOY_HOME/aws_resource_quota_validation.py