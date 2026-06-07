FROM php:8.3-cli

RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq-dev \
      libxml2-dev \
      libcurl4-openssl-dev \
      unzip \
    && docker-php-ext-install \
      pdo \
      pdo_pgsql \
      mbstring \
      bcmath \
      xml \
      tokenizer \
      ctype \
      curl \
      fileinfo \
      opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /app

EXPOSE 8099

CMD ["php", "-S", "0.0.0.0:8099", "-t", "/app/public"]
