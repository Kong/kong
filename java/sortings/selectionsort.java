import java.util.*;
public class Selection_Sort {
    static void select_sort(int Demo_Array[]) {
        int length = Demo_Array.length;

        // traversing the unsorted array
        for (int x = 0; x < length-1; x++) {
            // finding the minimum element in the array
            int minimum_index = x;
            for (int y = x+1; y < length; y++) {
                if (Demo_Array[y] < Demo_Array[minimum_index])
                    minimum_index = y;
            }
            // Swapping the elements
            int temp = Demo_Array[minimum_index];
            Demo_Array[minimum_index] = Demo_Array[x];
            Demo_Array[x] = temp;
        }
    }

    public static void main(String args[]){
        //Original Unsorted Array
        int Demo_Array[] = {6, 2, 1, 45, 23, 19, 63, 5, 43, 50};
        System.out.println("The Original Unsorted Array: \n" + Arrays.toString(Demo_Array));
        //call selection sort
        select_sort(Demo_Array);
        //print the sorted array
        System.out.println("Sorted Array By the Selection Sort: \n" + Arrays.toString(Demo_Array));
    }
}
