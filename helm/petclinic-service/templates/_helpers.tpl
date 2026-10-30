{{/*
Expand the name of the chart or service.
*/}}
{{- define "petclinic-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
Truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "petclinic-service.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Target namespace — explicit namespace in values takes precedence over Release.Namespace.
*/}}
{{- define "petclinic-service.namespace" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "petclinic-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels — immutable across chart/app upgrades, matching k8s/base/.
*/}}
{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic-service.name" . }}
app.kubernetes.io/part-of: petclinic
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "petclinic-service.labels" -}}
helm.sh/chart: {{ include "petclinic-service.chart" . }}
{{ include "petclinic-service.selectorLabels" . }}
app.kubernetes.io/component: {{ .Values.component | default "service" }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the ServiceAccount to use.
*/}}
{{- define "petclinic-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "petclinic-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the ConfigMap to use.
*/}}
{{- define "petclinic-service.configMapName" -}}
{{- default (printf "%s-config" (include "petclinic-service.fullname" .)) .Values.configMap.name }}
{{- end }}

{{/*
Construct the container image URI.
Prefers <image.registry>/<image.name>:<image.tag> when environment registry is set,
falling back to <image.repository>:<image.tag>.
*/}}
{{- define "petclinic-service.image" -}}
{{- $tag := .Values.image.tag | toString -}}
{{- if and .Values.image.registry .Values.image.name -}}
{{- printf "%s/%s:%s" .Values.image.registry .Values.image.name $tag -}}
{{- else if .Values.image.repository -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- else -}}
{{- printf "%s/%s:%s" (.Values.image.registry | default "037547369073.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev") (include "petclinic-service.name" .) $tag -}}
{{- end -}}
{{- end }}
