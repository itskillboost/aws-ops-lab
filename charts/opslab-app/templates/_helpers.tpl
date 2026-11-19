{{- define "opslab-app.labels" -}}
app.kubernetes.io/name: opslab-app
app.kubernetes.io/instance: {{ .Release.Name }}
course: opslab
{{- end }}
{{- define "opslab-app.selector" -}}
app.kubernetes.io/name: opslab-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
