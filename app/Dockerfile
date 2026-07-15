# ---------------------------------------------------------------------------
# Imagem base da aplicação: nginx (conforme permitido no desafio).
# A API real seria um serviço próprio; aqui o nginx serve uma página e um
# endpoint /healthz para os probes do Kubernetes.
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine

# Roda como usuário não-root por segurança (nginx-unprivileged pattern).
# A imagem oficial já traz o usuário "nginx" (uid 101).
RUN rm /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/conf.d/app.conf
COPY html/ /usr/share/nginx/html/

# Ajusta permissões para o usuário não-root.
# Os caminhos que o nginx precisa escrever em runtime (/var/cache/nginx, /run
# para o nginx.pid, e /tmp) recebem volumes emptyDir no Deployment, porque o
# Pod roda com readOnlyRootFilesystem: true.
RUN chown -R nginx:nginx /usr/share/nginx/html \
    && chown -R nginx:nginx /var/cache/nginx

USER nginx

EXPOSE 8080

# Healthcheck local da imagem (complementar aos probes do Kubernetes).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
