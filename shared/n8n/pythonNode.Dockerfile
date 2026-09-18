FROM n8nio/runners:2.6.2
USER root
RUN cd /opt/runners/task-runner-python && uv pip install pdfplumber
COPY n8n-task-runners.json /etc/n8n-task-runners.json
USER runner