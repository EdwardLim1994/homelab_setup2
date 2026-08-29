{{- define "kafka.labels" -}}
app.kubernetes.io/name: kafka
{{- end -}}

{{- define "kafkaUi.labels" -}}
app.kubernetes.io/name: kafka-ui
{{- end -}}
