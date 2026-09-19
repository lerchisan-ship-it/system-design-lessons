# Агрегатор заказов и службы доставки

## GET /orders/{id}

```mermaid
sequenceDiagram
participant Client
participant OrderSystem
participant DB

Client->>OrderSystem: GET /orders/{id}
activate OrderSystem

OrderSystem->>DB: Find order by id
activate DB
DB-->>OrderSystem: Query result
deactivate DB

   alt Order found
        OrderSystem-->>Client: 200 OK + Order data
    else Order not found
        OrderSystem-->>Client: 404 Not Found
    end

deactivate OrderSystem 
```
INPUT
| Имя параметра | Тип данных | Обязательность | Описание |
| ------- | ------- | ------- | ------- |
| user_id | UUID или Integer | yes | Идентификатор пользователя |
| delivery_address | String | yes | Адрес доставки |
| items | Array | yes | Состав заказа |

OUTPUT
| Имя параметра | Тип данных | Описание |
| ------- | ------- | ------- |
| order_id | UUID или Integer | Уникальный идентификатор заказа на доставку |
| status | String | Статус созданного заказа |
| delivery_slot | DateTime / String | Зарезервированный интервал доставки |

```plantuml
@startuml

participant Client
participant OrderSystem
database DB

Client -> OrderSystem: GET /orders/{id}
activate OrderSystem

OrderSystem -> DB: Find order by id
activate DB
DB --> OrderSystem: Query result
deactivate DB

alt Order found
    OrderSystem --> Client: 200 OK + Order data
else Order not found
    OrderSystem --> Client: 404 Not Found
end

deactivate OrderSystem

@enduml
```

### POST/orders
```mermaid
    sequenceDiagram
    participant Client
    participant OrderSystem
    participant DB
    participant DeliveryAPI

    Client->>OrderSystem: POST /orders
    activate OrderSystem

    OrderSystem->>DB: Save order with PENDING_DELIVERY
    activate DB
    DB-->>OrderSystem: Order saved, order_id
    deactivate DB

    Note over OrderSystem,DeliveryAPI: Same idempotency_key is used for retries

    loop Retry only after timeout (max 3 attempts)
        OrderSystem->>DeliveryAPI: Reserve slot (order_id, delivery_address, items, idempotency_key)
        activate DeliveryAPI

        alt Reservation confirmed
            DeliveryAPI-->>OrderSystem: 201 Created + delivery_id + delivery_slot

        else Invalid delivery data
            DeliveryAPI-->>OrderSystem: 400 Bad Request

        else Timeout
            Note over OrderSystem,DeliveryAPI: No response received within timeout
        end

        deactivate DeliveryAPI
    end

    alt Reservation confirmed
        OrderSystem->>DB: Update order status to CREATED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 201 Created + order_id + delivery_slot

    else 400 caused by invalid client data
        OrderSystem->>DB: Update order status to FAILED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 400 Bad Request

    else 400 caused by internal mapping error
        OrderSystem->>DB: Update order status to FAILED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 500 Internal Server Error

    else All attempts timed out
        OrderSystem->>DB: Update order status to FAILED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 504 Gateway Timeout
    end

    deactivate OrderSystem
```
INPUT
| Имя параметра | Тип данных | Обязательность | Описание |
| ------- | ------- | ------- | ------- |
| order_id | UUID или Integer | yes | Уникальный идентификатор заказа на доставку |
| delivery_address | String | yes | Адрес доставки |
| items | Array | yes | Состав заказа |
| idempotency_key | UUID / String | yes | Идентификатор операции для безопасного повторного запроса |

OUTPUT
| Имя параметра | Тип данных | Описание |
| ------- | ------- | ------- |
| delivery_id | UUID или Integer | Идентификатор созданного резервирования доставки |
| delivery_slot | DateTime / String | Зарезервированный интервал доставки |

Mapping table
| Поле нашей системы | Поле Delivery API | Логика преобразования |
| ------- | ------- | ------- |
| order_id | external_order_id | Передать без изменений |
| delivery_address | destination | Передать без изменений |
| items | cargo_items | Преобразовать элементы заказа в формат Delivery API |
| idempotency_key | Idempotency-Key | Передать в HTTP-заголовке; использовать тот же ключ для всех retry |

```plantuml
@startuml

participant Client
participant OrderSystem
database DB
participant DeliveryAPI

Client -> OrderSystem: POST /orders
activate OrderSystem

OrderSystem -> DB: Save order with PENDING_DELIVERY
activate DB
DB --> OrderSystem: Order saved, order_id
deactivate DB

note over OrderSystem, DeliveryAPI
Same idempotency_key is used for retries
end note

loop Retry after timeout, max 3 attempts
    OrderSystem -> DeliveryAPI: Reserve delivery slot
    activate DeliveryAPI

    alt Reservation confirmed
        DeliveryAPI --> OrderSystem: Slot reserved, delivery_id, delivery_slot

    else Invalid delivery data
        DeliveryAPI --> OrderSystem: 400 Bad Request

    else Timeout
        note over OrderSystem, DeliveryAPI
        No response received within timeout
        end note
    end

    deactivate DeliveryAPI
end

alt Reservation confirmed

    OrderSystem -> DB: Update order status to CREATED
    activate DB
    DB --> OrderSystem: Order updated
    deactivate DB

    OrderSystem --> Client: 201 Created + order_id + delivery_slot

else 400 caused by invalid client data

    OrderSystem -> DB: Update order status to FAILED
    activate DB
    DB --> OrderSystem: Order updated
    deactivate DB

    OrderSystem --> Client: 400 Bad Request

else 400 caused by internal mapping error

    OrderSystem -> DB: Update order status to FAILED
    activate DB
    DB --> OrderSystem: Order updated
    deactivate DB

    OrderSystem --> Client: 500 Internal Server Error

else All attempts timed out

    OrderSystem -> DB: Update order status to FAILED
    activate DB
    DB --> OrderSystem: Order updated
    deactivate DB

    OrderSystem --> Client: 504 Gateway Timeout

end

deactivate OrderSystem

@enduml
```