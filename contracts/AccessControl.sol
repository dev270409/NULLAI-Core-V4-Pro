// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

/**
 * @title NULLAIAccessControl
 * @author NULLAI Core Team
 * @notice Role hierarchy: Admin (10), Guardian (20), Operator (30).
 *
 * Role IDs start at 10 to avoid collision with OZ reserved values:
 *   - PUBLIC_ROLE = 0 (callable by anyone)
 *   - ADMIN_ROLE  = type(uint64).max (internal OZ admin)
 */
contract NULLAIAccessControl is AccessManager {

    uint64 public constant ADMIN_ROLE    = 10;
    uint64 public constant GUARDIAN_ROLE = 20;
    uint64 public constant OPERATOR_ROLE = 30;

    event ProtocolRolesInitialized(address indexed admin, address indexed guardian, address indexed operator);

    constructor(address daoMultisig, address guardian, address operatorBot) AccessManager(daoMultisig) {
        require(guardian != address(0) && operatorBot != address(0), "NULLAIAccessControl: zero address");

        _grantRole(ADMIN_ROLE,    daoMultisig, 0);
        _grantRole(GUARDIAN_ROLE, guardian,    0);
        _grantRole(OPERATOR_ROLE, operatorBot, 0);

        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);

        emit ProtocolRolesInitialized(daoMultisig, guardian, operatorBot);
    }
}
