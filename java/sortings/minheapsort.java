 
importjava.util.Scanner;  
  
// create class MinHeap to construct Min heap in Java  
classMinHeap {   
    // declare array and variables  
privateint[] heapData;   
privateintsizeOfHeap;   
privateintheapMaxSize;   
  
private static final int FRONT = 1;   
    //use constructor to initialize heapData array  
publicMinHeap(intheapMaxSize)  {   
this.heapMaxSize = heapMaxSize;   
this.sizeOfHeap = 0;   
heapData = new int[this.heapMaxSize + 1];   
heapData[0] = Integer.MIN_VALUE;   
    }   
  
    // create getParentPos() method that returns parent position for the node   
privateintgetParentPosition(int position)  {   
return position / 2;   
    }   
  
    // create getLeftChildPosition() method that returns the position of left child   
privateintgetLeftChildPosition(int position)  {   
return (2 * position);   
    }   
  
    // create getRightChildPosition() method that returns the position of right child  
privateintgetRightChildPosition(int position)  {   
return (2 * position) + 1;   
    }   
  
    // checks whether the given node is leaf or not  
privatebooleancheckLeaf(int position)  {   
if (position >= (sizeOfHeap / 2) && position <= sizeOfHeap) {   
return true;   
        }   
return false;   
    }   
  
    // create swapNodes() method that perform swapping of the given nodes of the heap   
    // firstNode and secondNode are the positions of the nodes  
private void swap(intfirstNode, intsecondNode)  {   
int temp;   
temp = heapData[firstNode];   
heapData[firstNode] = heapData[secondNode];   
heapData[secondNode] = temp;   
    }   
  
    // create minHeapify() method to heapify the node for maintaining the heap property  
private void minHeapify(int position)  {   
  
        //check whether the given node is non-leaf and greater than its right and left child  
if (!checkLeaf(position)) {   
if (heapData[position] >heapData[getLeftChildPosition(position)] || heapData[position] >heapData[getRightChildPosition(position)]) {   
  
                // swap with left child and then heapify the left child   
if (heapData[getLeftChildPosition(position)] <heapData[getRightChildPosition(position)]) {   
swap(position, getLeftChildPosition(position));   
minHeapify(getLeftChildPosition(position));   
                }   
  
                // Swap with the right child and heapify the right child   
else {   
swap(position, getRightChildPosition(position));   
minHeapify(getRightChildPosition(position));   
                }   
            }   
        }   
    }   
  
    // create insertNode() method to insert element in the heap  
public void insertNode(int data)  {   
if (sizeOfHeap>= heapMaxSize) {   
return;   
        }   
heapData[++sizeOfHeap] = data;   
int current = sizeOfHeap;   
  
while (heapData[current] <heapData[getParentPosition(current)]) {    
swap(current, getParentPosition(current));   
current = getParentPosition(current);   
        }   
    }   
  
    // crreatedisplayHeap() method to print the data of the heap   
public void displayHeap()  {   
System.out.println("PARENT NODE" + "\t" + "LEFT CHILD NODE" + "\t" + "RIGHT CHILD NODE");  
for (int k = 1; k <= sizeOfHeap / 2; k++) {   
System.out.print(" " + heapData[k] + "\t\t" + heapData[2 * k] + "\t\t" + heapData[2 * k + 1]);   
System.out.println();   
        }   
    }   
  
   // create designMinHeap() method to construct min heap  
public void designMinHeap()  {   
for (int position = (sizeOfHeap / 2); position >= 1; position--) {   
minHeapify(position);   
        }   
    }   
  
    // create removeRoot() method for removing minimum element from the heap  
publicintremoveRoot()  {   
intpopElement = heapData[FRONT];   
heapData[FRONT] = heapData[sizeOfHeap--];   
minHeapify(FRONT);   
returnpopElement;   
    }   
}  
  
// create MinHeapJavaImplementation class to create heap in Java  
classMinHeapJavaImplementation{  
      
    // main() method start  
public static void main(String[] arg)  {   
    // declare variable  
    intheapSize;  
      
    // create scanner class object  
    Scanner sc = new Scanner(System.in);  
      
    System.out.println("Enter the size of Min Heap");  
    heapSize = sc.nextInt();  
      
    MinHeapheapObj = new MinHeap(heapSize);  
      
    for(inti = 1; i<= heapSize; i++) {  
        System.out.print("Enter "+i+" element: ");  
        int data = sc.nextInt();  
        heapObj.insertNode(data);  
    }  
      
        // close scanner class obj  
sc.close();  
  
        //construct a min heap from given data  
heapObj.designMinHeap();   
  
        //display the min heap data  
System.out.println("The Min Heap is ");   
heapObj.displayHeap();   
  
        //removing the root node from the heap  
System.out.println("After removing the minimum element(Root Node) "+heapObj.removeRoot()+", Min heap is:");   
heapObj.displayHeap();   
  
    }   
}  
