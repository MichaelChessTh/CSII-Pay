"""
Generalized Sandboxed Smart Contract Engine for CSII-Pay Blockchain
Enables arbitrary smart contract deployment and execution with:
- AST-level security sandbox (no external OS, disk, network, or unsafe builtins)
- Gas/Step metering to deterministically prevent infinite loops and node freezing
- Isolated contract key-value storage and escrow balances (CSP & BDP)
- Atomic state rollback on revert or failure
"""

import ast
import hashlib
import json
import time
from typing import Dict, Any, Optional, Tuple, List

MAX_EXECUTION_STEPS = 50000

class SecurityError(Exception):
    """Raised when contract code violates the sandbox security policy."""
    pass

class GasExhaustionError(Exception):
    """Raised when contract code exceeds maximum allowed computation steps."""
    pass

class RevertError(Exception):
    """Raised when a contract explicitly reverts."""
    pass


# -------------------------------------------------------------
# AST Security Validator & Gas Injection Transformer
# -------------------------------------------------------------
class ContractSecurityValidator(ast.NodeVisitor):
    """
    Statically analyzes contract AST to forbid dangerous operations:
    - Imports, dynamic code execution (eval, exec, compile)
    - Private/dunder attributes (__class__, __subclasses__, etc.)
    - Non-deterministic or system builtins
    """
    FORBIDDEN_CALLS = {
        "eval", "exec", "compile", "open", "globals", "locals",
        "getattr", "setattr", "delattr", "__import__", "input",
        "exit", "quit", "breakpoint", "help", "memoryview"
    }

    def visit_Import(self, node):
        raise SecurityError("Imports are forbidden in smart contracts")

    def visit_ImportFrom(self, node):
        raise SecurityError("Imports are forbidden in smart contracts")

    def visit_Attribute(self, node):
        if node.attr.startswith("__"):
            raise SecurityError(f"Accessing private/dunder attribute '{node.attr}' is forbidden")
        self.generic_visit(node)

    def visit_Call(self, node):
        if isinstance(node.func, ast.Name) and node.func.id in self.FORBIDDEN_CALLS:
            raise SecurityError(f"Calling built-in function '{node.func.id}' is forbidden")
        self.generic_visit(node)


class GasStepTransformer(ast.NodeTransformer):
    """
    Injects `__step__()` calls into loop bodies and function entry points
    to meter execution steps deterministically.
    """
    def _create_step_call(self):
        return ast.Expr(
            value=ast.Call(
                func=ast.Name(id="__step__", ctx=ast.Load()),
                args=[],
                keywords=[]
            )
        )

    def visit_FunctionDef(self, node):
        self.generic_visit(node)
        step_call = self._create_step_call()
        node.body.insert(0, step_call)
        return node

    def visit_While(self, node):
        self.generic_visit(node)
        step_call = self._create_step_call()
        node.body.insert(0, step_call)
        return node

    def visit_For(self, node):
        self.generic_visit(node)
        step_call = self._create_step_call()
        node.body.insert(0, step_call)
        return node


# -------------------------------------------------------------
# Contract Execution Context
# -------------------------------------------------------------
class ContractContext:
    """
    Execution environment exposed to smart contract methods.
    Provides caller identity, storage access, escrow transfers, and event emission.
    """
    def __init__(
        self,
        contract_id: str,
        contract_owner: str,
        caller: str,
        timestamp: float,
        storage: Dict[str, Any],
        balances: Dict[str, float],
        attached_token: Optional[str] = None,
        attached_amount: float = 0.0
    ):
        self.contract_id = contract_id
        self.contract_owner = contract_owner
        self.caller = caller
        self.timestamp = timestamp
        self.storage = storage  # Persistent key-value store for this contract
        self.balances = balances  # Contract's token balance {"CSP": float, "BDP": float}
        self.attached_token = attached_token
        self.attached_amount = round(float(attached_amount), 6)
        self.payouts: List[Dict[str, Any]] = []
        self.events: List[Dict[str, Any]] = []

    def emit(self, event_name: str, data: Optional[Dict[str, Any]] = None):
        """Emits an event into the transaction receipt."""
        self.events.append({
            "contract_id": self.contract_id,
            "event": str(event_name),
            "data": data or {},
            "timestamp": self.timestamp
        })

    def transfer(self, recipient: str, token: str, amount: float):
        """
        Disburses tokens from the smart contract's balance to an account.
        Queued for atomic settlement upon successful transaction completion.
        """
        token = str(token).upper()
        amount = round(float(amount), 6)
        if token not in ("CSP", "BDP"):
            raise ValueError(f"Invalid token: {token}")
        if amount <= 0:
            raise ValueError(f"Transfer amount must be strictly positive: {amount}")

        current_bal = self.balances.get(token, 0.0)
        # Calculate pending payouts already queued for this token
        pending_out = sum(p["amount"] for p in self.payouts if p["token"] == token)
        if current_bal - pending_out < amount:
            raise ValueError(
                f"Insufficient contract balance in {token}. "
                f"Available: {current_bal - pending_out}, Requested: {amount}"
            )

        self.balances[token] = round(current_bal - amount, 6)
        self.payouts.append({
            "recipient": recipient,
            "token": token,
            "amount": amount
        })

    def get_balance(self, token: str = "CSP") -> float:
        """Returns the contract's balance in the specified token."""
        return self.balances.get(token.upper(), 0.0)


# -------------------------------------------------------------
# Smart Contract Engine
# -------------------------------------------------------------
class SmartContractEngine:
    """
    Compiles, validates, and executes smart contracts in a secure sandbox.
    """
    @staticmethod
    def validate_code(code: str) -> None:
        """Parses and runs static security validation on source code."""
        try:
            parsed = ast.parse(code)
        except SyntaxError as e:
            raise SecurityError(f"Syntax error in smart contract code: {e}")

        validator = ContractSecurityValidator()
        validator.visit(parsed)

    @staticmethod
    def compile_and_instrument(code: str) -> Any:
        """Instruments code with gas metering and compiles to code object."""
        SmartContractEngine.validate_code(code)
        parsed = ast.parse(code)
        transformer = GasStepTransformer()
        transformed = transformer.visit(parsed)
        ast.fix_missing_locations(transformed)
        return compile(transformed, filename="<contract>", mode="exec")

    @staticmethod
    def _create_safe_builtins(step_tracker: Dict[str, int]) -> Dict[str, Any]:
        """Provides restricted builtins and gas metering callback."""
        def step():
            step_tracker["steps"] += 1
            if step_tracker["steps"] > MAX_EXECUTION_STEPS:
                raise GasExhaustionError(f"Execution step limit exceeded ({MAX_EXECUTION_STEPS} steps)")

        def sha256(data):
            if isinstance(data, (dict, list)):
                s = json.dumps(data, sort_keys=True)
            else:
                s = str(data)
            return hashlib.sha256(s.encode("utf-8")).hexdigest()

        safe_builtins = {
            # Types & constructors
            "int": int,
            "float": float,
            "str": str,
            "bool": bool,
            "list": list,
            "dict": dict,
            "tuple": tuple,
            "set": set,
            # Safe math & utilities
            "len": len,
            "range": range,
            "min": min,
            "max": max,
            "abs": abs,
            "round": round,
            "sum": sum,
            "enumerate": enumerate,
            "zip": zip,
            "isinstance": isinstance,
            "Exception": Exception,
            "ValueError": ValueError,
            "KeyError": KeyError,
            # Cryptographic & gas primitives
            "sha256": sha256,
            "__step__": step
        }
        return safe_builtins

    @classmethod
    def execute(
        cls,
        code: str,
        method: str,
        context: ContractContext,
        kwargs: Dict[str, Any]
    ) -> Tuple[bool, Any, str]:
        """
        Executes a method in the smart contract sandbox.
        Returns (success, result, error_message).
        """
        step_tracker = {"steps": 0}
        safe_builtins = cls._create_safe_builtins(step_tracker)

        contract_globals = {
            "__builtins__": safe_builtins,
            "RevertError": RevertError
        }

        try:
            compiled_code = cls.compile_and_instrument(code)
            exec(compiled_code, contract_globals)
        except Exception as e:
            return False, None, f"Compilation/Deployment error: {e}"

        fn = contract_globals.get(method)
        if not fn or not callable(fn):
            return False, None, f"Method '{method}' not found or not callable in contract"

        try:
            result = fn(context, **kwargs)
            return True, result, ""
        except GasExhaustionError as ge:
            return False, None, f"Out of Gas: {ge}"
        except Exception as e:
            return False, None, f"Contract execution reverted: {e}"
