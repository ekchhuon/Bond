//
//  The MIT License (MIT)
//
//  Copyright (c) 2015 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

/// Abstraction over an event type generated by a Vector.
/// Vector event encapsulates current state of the vector, as well
/// as the operation that has triggered an event.
public protocol VectorEventType {
  typealias VectorEventSequenceType: SequenceType
  var sequence: VectorEventSequenceType { get }
  var operation: VectorOperation<VectorEventSequenceType.Generator.Element> { get }
}

/// A concrete vector event type.
public struct VectorEvent<VectorEventSequenceType: SequenceType>: VectorEventType {
  public let sequence: VectorEventSequenceType
  public let operation: VectorOperation<VectorEventSequenceType.Generator.Element>
}

/// Represents an operation that can be applied to a Vector.
/// Note: Nesting of the .Batch operations is not supported at the moment.
public indirect enum VectorOperation<ElementType> {
  case Insert(elements: [ElementType], fromIndex: Int)
  case Update(elements: [ElementType], fromIndex: Int)
  case Remove(range: Range<Int>)
  case Reset(array: [ElementType])
  case Batch([VectorOperation<ElementType>])
}

/// A vector event change set represents a description of the change that 
/// the vector event operation does to a vector in a way suited for application
/// to the UIKit collection views like UITableView or UICollectionView
public enum VectorEventChangeSet {
  case Inserts(Set<Int>)
  case Updates(Set<Int>)
  case Deletes(Set<Int>)
}

public func ==(lhs: VectorEventChangeSet, rhs: VectorEventChangeSet) -> Bool {
  switch (lhs, rhs) {
  case (.Inserts(let l), .Inserts(let r)):
    return l == r
  case (.Updates(let l), .Updates(let r)):
    return l == r
  case (.Deletes(let l), .Deletes(let r)):
    return l == r
  default:
    return false
  }
}

public extension VectorOperation {
  
  /// Maps elements encapsulated in the operation.
  public func map<X>(transform: ElementType -> X) -> VectorOperation<X> {
    switch self {
    case .Reset(let array):
      return .Reset(array: array.map(transform))
    case .Insert(let elements, let fromIndex):
      return .Insert(elements: elements.map(transform), fromIndex: fromIndex)
    case .Update(let elements, let fromIndex):
      return .Update(elements: elements.map(transform), fromIndex: fromIndex)
    case .Remove(let range):
      return .Remove(range: range)
    case .Batch(let operations):
      return .Batch(operations.map{ $0.map(transform) })
    }
  }
  
  public func filter(includeElement: ElementType -> Bool, inout pointers: [Int]) -> VectorOperation<ElementType>? {
    
    switch self {
    case .Insert(let elements, let fromIndex):
      
      for (index, element) in pointers.enumerate() {
        if element >= fromIndex {
          pointers[index] = element + elements.count
        }
      }
      
      var insertedIndices: [Int] = []
      var insertedElements: [ElementType] = []
      
      for (index, element) in elements.enumerate() {
        if includeElement(element) {
          insertedIndices.append(fromIndex + index)
          insertedElements.append(element)
        }
      }
      
      if insertedIndices.count > 0 {
        let insertionPoint = startingIndexForIndex(fromIndex, forPointers: pointers)
        pointers.splice(insertedIndices, atIndex: insertionPoint)
        return .Insert(elements: insertedElements, fromIndex: insertionPoint)
      }
      
    case .Update(let elements, let fromIndex):
      
      var operations: [VectorOperation<ElementType>] = []
      
      for (index, element) in elements.enumerate() {
        let realIndex = fromIndex + index
        
        // if element on this index is currently included in filtered array
        if let location = pointers.indexOf(realIndex) {
          if includeElement(element) {
            // update
            operations.append(.Update(elements: [element], fromIndex: location))
          } else {
            // remove
            pointers.removeAtIndex(location)
            operations.append(.Remove(range: location..<location+1))
          }
        } else { // element in this index is currently NOT included
          if includeElement(element) {
            // insert
            let insertionPoint = startingIndexForIndex(realIndex, forPointers: pointers)
            pointers.insert(realIndex, atIndex: insertionPoint)
            operations.append(.Insert(elements: [element], fromIndex: insertionPoint))
          } else {
            // not contained, not inserted - do nothing
          }
        }
      }
      
      if operations.count == 1 {
        return operations.first!
      } else if operations.count > 1 {
        return .Batch(operations)
      }
      
    case .Remove(let range):
      
      var startIndex = -1
      var endIndex = -1
      
      for (index, element) in pointers.enumerate() {
        if element >= range.startIndex {
          if element < range.endIndex {
            if startIndex < 0 {
              startIndex = index
              endIndex = index + 1
            } else {
              endIndex = index + 1
            }
          }
          
          pointers[index] = element - range.count
        }
      }
      
      if startIndex >= 0 {
        let removedRange = Range(start: startIndex, end: endIndex)
        pointers.removeRange(removedRange)
        return .Remove(range: removedRange)
      }
      
    case .Reset(let array):
      pointers = pointersFromSequence(array, includeElement: includeElement)
      return .Reset(array: array.filter(includeElement))
      
    case .Batch(let operations):
      
      var filteredOperations: [VectorOperation<ElementType>] = []
      
      for operation in operations {
        if let filtered = operation.filter(includeElement, pointers: &pointers) {
          filteredOperations.append(filtered)
        }
      }
      
      if filteredOperations.count == 1 {
        return filteredOperations.first!
      } else if filteredOperations.count > 0 {
        return .Batch(filteredOperations)
      }
    }
    
    return nil
  }
  
  /// Generates the `VectorEventChangeSet` representation of the operation.
  public func changeSet() -> VectorEventChangeSet {
    switch self {
    case .Insert(let elements, let fromIndex):
      return .Inserts(Set(fromIndex..<fromIndex+elements.count))
    case .Update(let elements, let fromIndex):
      return .Updates(Set(fromIndex..<fromIndex+elements.count))
    case .Remove(let range):
      return .Deletes(Set(range))
    case .Reset:
      fallthrough
    case .Batch:
      fatalError("Dear Sir/Madam, I cannot generate changeset for \(self) operation.")
    }
  }
}

internal func pointersFromSequence<S: SequenceType>(sequence: S, includeElement: S.Generator.Element -> Bool) -> [Int] {
  var pointers: [Int] = []
  for (index, element) in sequence.enumerate() {
    if includeElement(element) {
      pointers.append(index)
    }
  }
  return pointers
}

internal func startingIndexForIndex(x: Int, forPointers pointers: [Int]) -> Int {
  var idx: Int = -1
  for (index, element) in pointers.enumerate() {
    if element < x {
      idx = index
    } else {
      break
    }
  }
  return idx + 1
}


/// This function is used by UICollectionView and UITableView bindings.
/// Batch operations are expected to be sequentially applied to the vector/array, which is not what those views do.
/// The function converts operations into a "diff" discribing elements at what indices changed and in what way.
///
/// For example, when following (valid) input is given:
///   [.Insert([A], 0), .Insert([B], 0)]
/// function should produce following output:
///   [.Inserts([0, 1])]
///
/// Or:
///   [.Insert([B], 0), .Remove(1)] -> [.Inserts([0]), .Deletes([0])]
///   [.Insert([A], 0), .Insert([B], 0), .Remove(1)] -> [.Inserts([0])]
///   [.Insert([A], 0), .Remove(0)] -> []
///   [.Insert([A, B], 0), .Insert([C, D], 1)] -> [.Inserts([0, 1, 2, 3])]
///
public func changeSetsFromBatchOperations<T>(operations: [VectorOperation<T>]) -> [VectorEventChangeSet] {
  
  func shiftSet(set: Set<Int>, from: Int, by: Int) -> Set<Int> {
    var shiftedSet = Set<Int>()
    
    for element in set {
      if element >= from {
        shiftedSet.insert(element + by)
      } else {
        shiftedSet.insert(element)
      }
    }
    
    return shiftedSet
  }
  
  var inserts = Set<Int>()
  var updates = Set<Int>()
  var deletes = Set<Int>()
  
  for operation in operations {
    switch operation {
    case .Insert(let elements, let fromIndex):
      
      inserts = shiftSet(inserts, from: fromIndex, by: elements.count)
      updates = shiftSet(updates, from: fromIndex, by: elements.count)
      
      let range = fromIndex..<fromIndex+elements.count
      let replaced = deletes.intersect(range)
      let new = Set(range).subtract(replaced)
      
      deletes.subtractInPlace(replaced)
      updates.unionInPlace(replaced)
      deletes = shiftSet(deletes, from: fromIndex, by: elements.count)
      
      inserts.unionInPlace(new)
    case .Update(let elements, let fromIndex):
      updates.unionInPlace(fromIndex..<fromIndex+elements.count)
    case .Remove(let range):
      let annihilated = inserts.intersect(range)
      let reallyRemoved = Set(range).subtract(annihilated)

      inserts.subtractInPlace(annihilated)
      updates.subtractInPlace(range)

      inserts = shiftSet(inserts, from: range.startIndex, by: -range.count)
      updates = shiftSet(updates, from: range.startIndex, by: -range.count)
      deletes = shiftSet(deletes, from: range.startIndex, by: -range.count)
      
      deletes.unionInPlace(reallyRemoved)
    case .Reset:
      fatalError("Dear Sir/Madam, the .Reset operation within the .Batch is not supported at the moment!")
    case .Batch:
      fatalError("Dear Sir/Madam, nesting the .Batch operations is not supported at the moment!")
    }
  }
  
  var changeSets: [VectorEventChangeSet] = []
  
  if inserts.count > 0 {
    changeSets.append(.Inserts(inserts))
  }
  
  if updates.count > 0 {
    changeSets.append(.Updates(updates))
  }
  
  if deletes.count > 0 {
    changeSets.append(.Deletes(deletes))
  }
  
  return changeSets
}
