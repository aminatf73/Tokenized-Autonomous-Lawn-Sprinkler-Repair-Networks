import { describe, it, expect, beforeEach } from "vitest"

// Mock Parts Replacement contract
const mockPartsContract = {
  totalParts: 0,
  totalOrders: 0,
  partsTokenSupply: 0,
  partsInventory: new Map(),
  partsOrders: new Map(),
  installationRecords: new Map(),
  userPartsTokens: new Map(),
  authorizedSuppliers: new Map(),
  authorizedInstallers: new Map(),
  contractOwner: "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM",
  currentBlock: 1000,
}

const addPartToInventory = (
    partId,
    name,
    category,
    manufacturer,
    model,
    quantity,
    unitPrice,
    compatibility,
    warrantyPeriod,
    sender,
) => {
  if (!mockPartsContract.authorizedSuppliers.has(sender) && sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  if (mockPartsContract.partsInventory.has(partId)) {
    return { error: "ERR_PART_EXISTS" }
  }
  
  mockPartsContract.partsInventory.set(partId, {
    name: name,
    category: category,
    manufacturer: manufacturer,
    model: model,
    quantity: quantity,
    unitPrice: unitPrice,
    compatibility: compatibility,
    warrantyPeriod: warrantyPeriod,
    active: true,
  })
  
  mockPartsContract.totalParts++
  
  const currentBalance = mockPartsContract.userPartsTokens.get(sender) || 0
  mockPartsContract.userPartsTokens.set(sender, currentBalance + 20)
  mockPartsContract.partsTokenSupply += 20
  
  return { success: partId }
}

const updateInventory = (partId, newQuantity, sender) => {
  if (!mockPartsContract.authorizedSuppliers.has(sender) && sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  if (!mockPartsContract.partsInventory.has(partId)) {
    return { error: "ERR_INVALID_PART" }
  }
  
  const part = mockPartsContract.partsInventory.get(partId)
  mockPartsContract.partsInventory.set(partId, {
    ...part,
    quantity: newQuantity,
  })
  
  const currentBalance = mockPartsContract.userPartsTokens.get(sender) || 0
  mockPartsContract.userPartsTokens.set(sender, currentBalance + 10)
  mockPartsContract.partsTokenSupply += 10
  
  return { success: true }
}

const placePartsOrder = (partId, quantity, sender) => {
  if (!mockPartsContract.partsInventory.has(partId)) {
    return { error: "ERR_INVALID_PART" }
  }
  
  const part = mockPartsContract.partsInventory.get(partId)
  if (part.quantity < quantity) {
    return { error: "ERR_INSUFFICIENT_INVENTORY" }
  }
  
  const orderId = mockPartsContract.totalOrders + 1
  const totalCost = part.unitPrice * quantity
  
  mockPartsContract.partsOrders.set(orderId, {
    customer: sender,
    partId: partId,
    quantity: quantity,
    totalCost: totalCost,
    orderDate: mockPartsContract.currentBlock,
    status: "pending",
    technician: null,
    installationDate: null,
    completed: false,
  })
  
  // Update inventory
  mockPartsContract.partsInventory.set(partId, {
    ...part,
    quantity: part.quantity - quantity,
  })
  
  mockPartsContract.totalOrders = orderId
  
  const currentBalance = mockPartsContract.userPartsTokens.get(sender) || 0
  mockPartsContract.userPartsTokens.set(sender, currentBalance + 15)
  mockPartsContract.partsTokenSupply += 15
  
  return { success: orderId }
}

const assignInstaller = (orderId, technician, sender) => {
  if (!mockPartsContract.authorizedSuppliers.has(sender) && sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  if (!mockPartsContract.partsOrders.has(orderId)) {
    return { error: "ERR_ORDER_NOT_FOUND" }
  }
  if (!mockPartsContract.authorizedInstallers.has(technician)) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  
  const order = mockPartsContract.partsOrders.get(orderId)
  mockPartsContract.partsOrders.set(orderId, {
    ...order,
    technician: technician,
    status: "assigned",
  })
  
  return { success: true }
}

const completeInstallation = (orderId, systemId, notes, sender) => {
  if (!mockPartsContract.partsOrders.has(orderId)) {
    return { error: "ERR_ORDER_NOT_FOUND" }
  }
  if (!mockPartsContract.authorizedInstallers.has(sender)) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  
  const order = mockPartsContract.partsOrders.get(orderId)
  const installationId = orderId + mockPartsContract.currentBlock
  
  // Update order
  mockPartsContract.partsOrders.set(orderId, {
    ...order,
    status: "completed",
    installationDate: mockPartsContract.currentBlock,
    completed: true,
  })
  
  // Create installation record
  mockPartsContract.installationRecords.set(installationId, {
    orderId: orderId,
    systemId: systemId,
    partId: order.partId,
    technician: sender,
    installationDate: mockPartsContract.currentBlock,
    warrantyStart: mockPartsContract.currentBlock,
    notes: notes,
    verified: false,
  })
  
  const currentBalance = mockPartsContract.userPartsTokens.get(sender) || 0
  mockPartsContract.userPartsTokens.set(sender, currentBalance + 50)
  mockPartsContract.partsTokenSupply += 50
  
  return { success: installationId }
}

const verifyInstallation = (installationId, sender) => {
  if (!mockPartsContract.authorizedSuppliers.has(sender) && sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  if (!mockPartsContract.installationRecords.has(installationId)) {
    return { error: "ERR_ORDER_NOT_FOUND" }
  }
  
  const installation = mockPartsContract.installationRecords.get(installationId)
  mockPartsContract.installationRecords.set(installationId, {
    ...installation,
    verified: true,
  })
  
  const currentBalance = mockPartsContract.userPartsTokens.get(sender) || 0
  mockPartsContract.userPartsTokens.set(sender, currentBalance + 25)
  mockPartsContract.partsTokenSupply += 25
  
  return { success: true }
}

const cancelOrder = (orderId, sender) => {
  if (!mockPartsContract.partsOrders.has(orderId)) {
    return { error: "ERR_ORDER_NOT_FOUND" }
  }
  
  const order = mockPartsContract.partsOrders.get(orderId)
  if (order.customer !== sender) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  
  // Restore inventory
  const part = mockPartsContract.partsInventory.get(order.partId)
  mockPartsContract.partsInventory.set(order.partId, {
    ...part,
    quantity: part.quantity + order.quantity,
  })
  
  // Update order status
  mockPartsContract.partsOrders.set(orderId, {
    ...order,
    status: "cancelled",
  })
  
  return { success: true }
}

const authorizeSupplier = (supplier, specialization, sender) => {
  if (sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  
  mockPartsContract.authorizedSuppliers.set(supplier, {
    authorized: true,
    rating: 5,
    specialization: specialization,
  })
  
  return { success: true }
}

const authorizeInstaller = (installer, certification, sender) => {
  if (sender !== mockPartsContract.contractOwner) {
    return { error: "ERR_UNAUTHORIZED" }
  }
  
  mockPartsContract.authorizedInstallers.set(installer, {
    authorized: true,
    certification: certification,
    rating: 5,
  })
  
  return { success: true }
}

describe('Parts Replacement Contract', () => {
  beforeEach(() => {
    mockPartsContract.totalParts = 0;
    mockPartsContract.totalOrders = 0;
    mockPartsContract.partsTokenSupply = 0;
    mockPartsContract.partsInventory.clear();
    mockPartsContract.partsOrders.clear();
    mockPartsContract.installationRecords.clear();
    mockPartsContract.userPartsTokens.clear();
    mockPartsContract.authorizedSuppliers.clear();
    mockPartsContract.authorizedInstallers.clear();
    mockPartsContract.currentBlock = 1000;
  });
  
  describe('Inventory Management', () => {
    it('should allow authorized suppliers to add parts', () => {
      const owner = mockPartsContract.contractOwner;
      const result = addPartToInventory(1, 'Spray Nozzle', 'nozzles', 'RainBird', 'RB-15', 50, 25, 'All RainBird systems', 365, owner);
      
      expect(result.success).toBe(1);
      expect(mockPartsContract.totalParts).toBe(1);
      expect(mockPartsContract.partsInventory.get(1)).toEqual({
        name: 'Spray Nozzle',
        category: 'nozzles',
        manufacturer: 'RainBird',
        model: 'RB-15',
        quantity: 50,
        unitPrice: 25,
        compatibility: 'All RainBird systems',
        warrantyPeriod: 365,
        active: true
      });
      expect(mockPartsContract.userPartsTokens.get(owner)).toBe(20);
    });
    
    it('should reject unauthorized inventory additions', () => {
      const unauthorized = 'ST2UNAUTHORIZED';
      const result = addPartToInventory(1, 'Spray Nozzle', 'nozzles', 'RainBird', 'RB-15', 50, 25, 'All RainBird systems', 365, unauthorized);
      
      expect(result.error).toBe('ERR_UNAUTHORIZED');
      expect(mockPartsContract.totalParts).toBe(0);
    });
    
    it('should prevent duplicate part IDs', () => {
      const owner = mockPartsContract.contractOwner;
      addPartToInventory(1, 'Spray Nozzle', 'nozzles', 'RainBird', 'RB-15', 50, 25, 'All RainBird systems', 365, owner);
      const result = addPartToInventory(1, 'Different Part', 'valves', 'Hunter', 'H-20', 30, 40, 'Hunter systems', 730, owner);
      
      expect(result.error).toBe('ERR_PART_EXISTS');
    });
    
    it('should allow authorized suppliers to update inventory', () => {
      const owner = mockPartsContract.contractOwner;
      addPartToInventory(1, 'Spray Nozzle', 'nozzles', 'RainBird', 'RB-15', 50, 25, 'All RainBird systems', 365, owner);
      const result = updateInventory(1, 75, owner);
      
      expect(result.success).toBe(true);
      expect(mockPartsContract.partsInventory.get(1).quantity).toBe(75);
      expect(mockPartsContract.userPartsTokens.get(owner)).toBe(30); // 20 + 10
    });
  });
  
  describe('Order Management', () => {
    beforeEach(() => {
      const owner = mockPartsContract.contractOwner;
      addPartToInventory(1, 'Spray Nozzle', 'nozzles', 'RainBird', 'RB-15', 50, 25, 'All RainBird systems', 365, owner);
    });
    
    it('should allow customers to place orders', () => {
      const customer = 'ST2CUSTOMER';
      const result = placePartsOrder(1, 5, customer);
      
      expect(result.success).toBe(1);
      expect(mockPartsContract.totalOrders).toBe(1);
