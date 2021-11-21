FROM busybox

RUN wget -O terraform.zip 'https://releases.hashicorp.com/terraform/1.0.10/terraform_1.0.10_linux_amd64.zip' \
  && wget -O helm.tar.gz 'https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz' \
  && unzip terraform.zip \
  && tar -xzf helm.tar.gz --strip-components=1 

FROM debian:11.1-slim

ARG KUBERNETES_VERSION
ENV KUBERNETES_VERSION=$KUBERNETES_VERSION
ENV HELM_CACHE_HOME=/wd/terraform/helm/cache
ENV HELM_CONFIG_HOME=/wd/terraform/helm/config
ENV HELM_DATA_HOME=/wd/terraform/helm/local

ENV TF_VAR_volume_source=replacemeruntime

COPY --from=0 /terraform /bin/terraform
COPY --from=0 /helm /bin/helm
RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y genisoimage ansible jq curl \
  && curl -o /bin/kubectl -L "https://dl.k8s.io/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl" \
  && /bin/bash -c \
    "echo '$(curl -L https://dl.k8s.io/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl.sha256) /bin/kubectl'" \
    | sha256sum --check  \
  && chmod +x /bin/kubectl \
  && mkdir /wd

WORKDIR /wd

ADD . /wd/

RUN cd ./terraform \
  && terraform init

RUN cd ./tf_helm \
  && terraform init

VOLUME /wd/terraform
VOLUME /wd/tf_helm

ENTRYPOINT ["/bin/bash"]
