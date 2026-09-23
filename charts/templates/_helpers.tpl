{{/*
Expand the name of the chart.
*/}}
{{- define "rustdesk.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully qualified app name.
*/}}
{{- define "rustdesk.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart name and version for helm.sh/chart label.
*/}}
{{- define "rustdesk.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to all resources.
*/}}
{{- define "rustdesk.labels" -}}
helm.sh/chart: {{ include "rustdesk.chart" .context }}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- if .context.Chart.AppVersion }}
app.kubernetes.io/version: {{ .context.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels for matching pods to deployments/services.
*/}}
{{- define "rustdesk.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Component fullname: <fullname>-<component>
*/}}
{{- define "rustdesk.componentName" -}}
{{- printf "%s-%s" (include "rustdesk.fullname" .context) .component -}}
{{- end -}}

{{/*
Whether OAuth2 is enabled (existingSecret provided or oidcMock enabled).
*/}}
{{- define "rustdesk.oauth2Enabled" -}}
{{- if or .Values.hbbs.oauth2.existingSecret (and .Values.oidcMock.enabled .Values.oidcMock.authorizeUrl) -}}
true
{{- end -}}
{{- end -}}

{{/*
Name of the Secret containing oauth2.toml.
*/}}
{{- define "rustdesk.oauth2SecretName" -}}
{{- if .Values.hbbs.oauth2.existingSecret -}}
{{- .Values.hbbs.oauth2.existingSecret -}}
{{- else -}}
{{- .Release.Name }}-hbbs-oauth2
{{- end -}}
{{- end -}}

{{/*
Image reference with global registry override.
*/}}
{{- define "rustdesk.image" -}}
{{- $registry := .global.imageRegistry | default .image.registry -}}
{{- if $registry -}}
{{ $registry }}/{{ .image.repository }}:{{ .image.tag }}
{{- else -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}
{{- end -}}

{{/*
Fail on invalid database settings.
*/}}
{{- define "rustdesk.validateDatabase" -}}
{{- if .Values.postgresql.enabled -}}
{{- if or .Values.database.url .Values.database.existingSecret -}}
{{- fail "database.url/database.existingSecret must not be set when postgresql.enabled=true" -}}
{{- end -}}
{{- else if not (or .Values.database.url .Values.database.existingSecret) -}}
{{- fail "postgresql.enabled=false requires database.url or database.existingSecret" -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding the bundled Postgres password.
*/}}
{{- define "rustdesk.postgresql.secretName" -}}
{{- .Values.postgresql.auth.existingSecret | default (include "rustdesk.componentName" (dict "context" . "component" "postgresql")) -}}
{{- end -}}

{{/*
Database env vars for an app container. Usage:
  env:
    {{- include "rustdesk.databaseEnv" (dict "context" $ "var" "DB_URL") | nindent 12 }}
Both apps call this, so they always point at the same database.
*/}}
{{- define "rustdesk.databaseEnv" -}}
{{- $ctx := .context -}}
{{- include "rustdesk.validateDatabase" $ctx -}}
{{- if $ctx.Values.postgresql.enabled -}}
{{- $host := include "rustdesk.componentName" (dict "context" $ctx "component" "postgresql") -}}
- name: DATABASE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "rustdesk.postgresql.secretName" $ctx }}
      key: password
- name: {{ .var }}
  value: {{ printf "postgres://%s:$(DATABASE_PASSWORD)@%s:5432/%s" $ctx.Values.postgresql.auth.username $host $ctx.Values.postgresql.auth.database | quote }}
{{- else if $ctx.Values.database.existingSecret -}}
- name: {{ .var }}
  valueFrom:
    secretKeyRef:
      name: {{ $ctx.Values.database.existingSecret }}
      key: {{ $ctx.Values.database.existingSecretKey }}
{{- else -}}
- name: {{ .var }}
  valueFrom:
    secretKeyRef:
      name: {{ include "rustdesk.componentName" (dict "context" $ctx "component" "database") }}
      key: url
{{- end -}}
{{- end -}}
