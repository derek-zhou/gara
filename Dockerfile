# this is a multiarch image with 64 bit kernel and a 32 bit userland.
# if you cannot build the release in 32 bit to be compatible with debian
# bullseye please use Dockerfiles_2steps for safety

FROM "multiarch/debian-debootstrap:i386-bullseye-slim"

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Only copy the final release from the build stage
COPY --chown=nobody:root _build/prod/rel ./

USER nobody

# Create a symlink to the application directory by extracting the directory name. This is required
# since the release directory will be named after the application, and we don't know that name.
RUN set -eux; \
  ln -nfs /app/$(basename *)/bin/$(basename *) /app/entry

CMD /app/entry start

