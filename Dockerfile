FROM hashicorp/terraform:latest
RUN apk add py3-pip gcc musl-dev python3-dev libffi-dev openssl-dev cargo make
RUN pip install --upgrade pip
RUN pip install azure-cli
ENTRYPOINT [""]
