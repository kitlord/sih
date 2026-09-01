import strawberry

from traceability.graphql.mutations import Mutation
from traceability.graphql.queries import Query

schema = strawberry.Schema(query=Query, mutation=Mutation)
