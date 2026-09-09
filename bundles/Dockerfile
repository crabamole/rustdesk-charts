ARG RUSTDESK_VERSION=1.4.9

FROM alpine:3.20 AS download

ARG RUSTDESK_VERSION
RUN apk add --no-cache curl

WORKDIR /installers

RUN curl -fsSL -o rustdesk-${RUSTDESK_VERSION}-x86_64.msi \
      "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.msi" && \
    curl -fsSL -o rustdesk-${RUSTDESK_VERSION}-x86_64.exe \
      "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.exe" && \
    curl -fsSL -o rustdesk-${RUSTDESK_VERSION}-aarch64.dmg \
      "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-aarch64.dmg" && \
    curl -fsSL -o rustdesk-${RUSTDESK_VERSION}-x86_64.deb \
      "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.deb" && \
    curl -fsSL -o rustdesk-${RUSTDESK_VERSION}-x86_64.AppImage \
      "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-x86_64.AppImage"

FROM alpine:3.20

ARG RUSTDESK_VERSION
ENV RUSTDESK_VERSION=${RUSTDESK_VERSION}

WORKDIR /bundles

COPY --from=download /installers/ ./installers/
COPY README.md .
COPY entrypoint.sh .

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
