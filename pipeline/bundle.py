"""Validated relational bundles for automatic downstream loading."""
import sys,json
from pathlib import Path
from typing import Literal
from uuid import UUID
from pydantic import BaseModel,ConfigDict,Field,model_validator
sys.path.insert(0,str(Path(__file__).resolve().parent/"direct"))
from loader import manifest_check
class Bundle(BaseModel):
    model_config=ConfigDict(extra="forbid")
    schema_version:Literal[1]=1
    event_type:Literal["relational_bundle"]="relational_bundle"
    event_id:UUID
    manifest:list=Field(min_length=2,max_length=100)
    @model_validator(mode="after")
    def contract(self):
        try:manifest_check(self.manifest)
        except (ValueError,KeyError,TypeError,AttributeError) as e:raise ValueError("Invalid relational manifest") from e
        if len(json.dumps(self.manifest,ensure_ascii=False).encode())>65536:raise ValueError("Bundle exceeds 64KB")
        return self
