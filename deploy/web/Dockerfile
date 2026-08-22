# syntax=docker/dockerfile:1

FROM ghcr.io/cirruslabs/flutter:stable AS build
ARG APP_VERSION=0.1.0
WORKDIR /src
COPY apps/flutter/pubspec.yaml apps/flutter/pubspec.lock ./
RUN flutter pub get
COPY apps/flutter/ ./
RUN flutter build web --release --build-name "$APP_VERSION" --build-number 1

FROM nginx:1.29-alpine
LABEL org.opencontainers.image.title="qingxu-web" \
      org.opencontainers.image.source="https://github.com/FelixZoe/qingxu"
COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
EXPOSE 80
