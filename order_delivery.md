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

#### POST /orders

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

   loop While reservation not confirmed and attempts < 3
    OrderSystem->>DeliveryAPI: Reserve delivery slot (order_id, delivery_address, items, idempotency_key)
    activate DeliveryAPI

    alt Reservation confirmed
        DeliveryAPI-->>OrderSystem: Slot reserved, delivery_id, delivery_slot
    else Timeout
        Note over OrderSystem,DeliveryAPI: Retry only if attempts remain
    end

    deactivate DeliveryAPI
   end

    alt Reservation confirmed
        OrderSystem->>DB: Update order status to CREATED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 201 Created + order_id + delivery_slot

    else All attempts timed out
        OrderSystem->>DB: Update order status to FAILED
        activate DB
        DB-->>OrderSystem: Order updated
        deactivate DB

        OrderSystem-->>Client: 503 Service Unavailable
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