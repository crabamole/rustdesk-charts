{{- define "rustdesk.image" -}}
{{- $registry := .global.imageRegistry | default .image.registry -}}
{{- if $registry -}}
{{ $registry }}/{{ .image.repository }}:{{ .image.tag }}
{{- else -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}
{{- end -}}
