# KServe

## Inference Logger
https://kserve.github.io/website/docs/model-serving/predictive-inference/logger?_highlight=logger

## Basic Logger
 - [KNative message dumper](https://kserve.github.io/website/docs/model-serving/predictive-inference/logger/basic-logger)

KServe agent Sidecar: Intercepta a requisição/resposta e a envia como um [CloudEvent](https://cloudevents.io/) via HTTP POST.

event_display Service: Este é o nosso novo sink. Ele recebe o POST, imprime o corpo inteiro do CloudEvent (já em um formato legível) em seu stdout.

Fluent Bit DaemonSet: Coleta o log do stdout do pod event_display.

Loki & Grafana: Armazena e exibe os logs.