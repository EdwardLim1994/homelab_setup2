{{- define "prometheus.labels" -}}
app.kubernetes.io/name: prometheus
{{- end -}}

{{- define "loki.labels" -}}
app.kubernetes.io/name: loki
{{- end -}}

{{- define "tempo.labels" -}}
app.kubernetes.io/name: tempo
{{- end -}}

{{- define "grafana.labels" -}}
app.kubernetes.io/name: grafana
{{- end -}}

{{- define "otelCollector.labels" -}}
app.kubernetes.io/name: otel-collector
{{- end -}}

{{- define "nodeExporter.labels" -}}
app.kubernetes.io/name: node-exporter
{{- end -}}

{{- define "kubeStateMetrics.labels" -}}
app.kubernetes.io/name: kube-state-metrics
{{- end -}}

{{- define "alloy.labels" -}}
app.kubernetes.io/name: alloy
{{- end -}}
