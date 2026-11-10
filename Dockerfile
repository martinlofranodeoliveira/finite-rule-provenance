FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS preparation
COPY qualification/deb-packages.txt qualification/deb-files.sha256 /prepared/
WORKDIR /prepared
RUN apt-get -o APT::Sandbox::User=root update \
 && apt-get -o APT::Sandbox::User=root download $(cat deb-packages.txt) \
 && sha256sum --check --strict deb-files.sha256

FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS sdk
COPY --from=preparation /prepared /tmp/debs
RUN dpkg -i /tmp/debs/*.deb && rm -rf /tmp/debs \
 && mkdir -p /work/source /work/home /work/artifacts /work/consumer \
 && chown -R 1000:1000 /work
COPY --chown=1000:1000 . /work/source
WORKDIR /work/source
ENV HOME=/work/home
USER 1000:1000

FROM sdk AS compiled
RUN --network=none mv tests /work/source-tests && /bin/sh scripts/build-offline.sh

FROM debian@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS runtime
COPY --from=sdk /lib/x86_64-linux-gnu/libz.so.1.2.13 /lib/x86_64-linux-gnu/libz.so.1
COPY --from=sdk /lib/x86_64-linux-gnu/liblz4.so.1.9.4 /lib/x86_64-linux-gnu/liblz4.so.1
COPY --from=sdk /lib/x86_64-linux-gnu/libsqlite3.so.0.8.6 /lib/x86_64-linux-gnu/libsqlite3.so.0
RUN mkdir -p /work/app /work/notices && chown -R 1000:1000 /work
COPY --from=compiled --chown=1000:1000 /work/source/dist/distribution /work/app
COPY --from=compiled --chown=1000:1000 /work/source/third_party /work/notices
COPY --from=compiled --chown=1000:1000 /work/source/LICENSE /work/source/THIRD_PARTY_NOTICES.md /work/notices/
WORKDIR /work
ENV HOME=/tmp
USER 1000:1000
ENTRYPOINT ["/work/app/bin/finite-rule-provenance"]
CMD ["demo", "--assert"]
